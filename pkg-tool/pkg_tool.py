import argparse
import datetime
import hashlib
import io
import json
import os
import shutil
import tarfile
import urllib.request

import yaml
import zstandard as zstd
from jinja2 import Environment, FileSystemLoader

"""
FreeBSD Custom Package Repository CLI

This module provides functionality to pack staged payloads into FreeBSD
packages, to redistribute packages, and to generate the metadata FreeBSD's
pkg tooling needs for custom package repositories.

Usage:
    pkg-tool <command> [options]

Commands:
    pack                Pack a staged payload into a FreeBSD package.
    redistribute-pkg    Redistribute package.

Examples:
    pkg-tool pack ./config.yml --abi 15 --arch amd64
    pkg-tool redistribute-pkg ./config.yml --abi 14 --arch amd64
"""

def _create_manifest(config_path, abi, arch, payload_dir, output_dir='.'):
    """
    Create manifest files from a staged payload.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
        payload_dir (str): Directory containing the staged payload.
        output_dir (str): Directory to output the manifest files. Defaults to the current directory.
    """
    if not os.path.isdir(payload_dir):
        raise FileNotFoundError(f"Payload directory not found: {payload_dir}")
    with open(config_path, "r") as f:
        pkg_config = yaml.safe_load(f)
    manifest = pkg_config["pkg_manifest"]
    manifest['version'] = str(manifest['version'])
    manifest['abi'] = f'FreeBSD:{abi}:{arch}'
    manifest['arch'] = manifest['abi'].lower().replace('amd64', 'x86:64')
    manifest['flatsize'] = _folder_size(payload_dir)

    manifest['files'] = {}
    for root, _, files in os.walk(payload_dir):
        for file in sorted(files):
            file_path = os.path.join(root, file)
            manifest['files'][f'{os.sep}{os.path.relpath(file_path, payload_dir)}'] = _sha256sum(file_path)

    with open(os.path.join(output_dir, '+MANIFEST'), "w") as f:
        json.dump(manifest, f, separators=(',', ':'))

    manifest.pop('files', None)
    manifest.pop('scripts', None)

    with open(os.path.join(output_dir, '+COMPACT_MANIFEST'), "w") as f:
        json.dump(manifest, f, separators=(',', ':'))

def _create_packagesite_info(compact_manifest_path, output_dir='.'):
    """
    Create package site information file.

    Args:
        compact_manifest_path (str): Path to the +COMPACT_MANIFEST file.
        output_dir (str): Directory to output the packagesite info file. Defaults to the current directory.
    """
    with open(compact_manifest_path, "r") as f:
        pkg_info = json.load(f)

    pkg = _pkg_filename(pkg_info['name'], pkg_info['version'])
    pkg_path = os.path.join(output_dir, pkg)

    pkg_info['path'] = f'All/{pkg}'
    pkg_info['repopath'] = f'All/{pkg}'
    pkg_info['sum'] = f'{_sha256sum(pkg_path)}'
    pkg_info['pkgsize'] = os.path.getsize(pkg_path)

    with open(os.path.join(output_dir, 'packagesite_info.json'), "w") as f:
        json.dump(pkg_info, f, separators=(',', ':'))

def _pkg_filename(name, version):
    return f'{name}-{version}.pkg'

def _pinned_tarinfo(tar, path, arcname):
    """TarInfo with the reproducible metadata every package member carries."""
    info = tar.gettarinfo(path)
    info.name = arcname
    info.uid = 0
    info.gid = 0
    info.uname = ''
    info.gname = ''
    info.mtime = 0
    return info

def assemble_repo(artifacts_dir, repo_config_path, owner, repo, output_dir='pages'):
    """
    Assemble the published repo tree from built packages.

    Takes a directory of build outputs (each .pkg next to its
    packagesite_info.json, or a bare .pkg) and produces the complete
    serveable tree: FreeBSD:<abi>:<arch>/latest/... layout, accumulated
    packagesite.yaml packed into packagesite.tzst + symlink, meta.conf,
    opnware.conf, robots.txt and index pages. abi/arch come from each
    artifact's own manifest and are validated against the repo config.

    Args:
        artifacts_dir (str): Directory containing the build outputs.
        repo_config_path (str): Path to the repo-level config.yml.
        owner (str): GitHub owner, used in the opnware.conf URL.
        repo (str): GitHub repo name, used in the opnware.conf URL.
        output_dir (str): Directory to output the repo tree. Defaults to 'pages'.
    """
    if not os.path.isdir(artifacts_dir):
        raise FileNotFoundError(f"Artifacts directory not found: {artifacts_dir}")
    with open(repo_config_path, "r") as f:
        repo_config = yaml.safe_load(f)
    declared_abis = [str(a) for a in repo_config.get('pkg-repo', {}).get('abi', [])]
    declared_archs = [str(a) for a in repo_config.get('pkg-repo', {}).get('arch', [])]

    pkg_files = []
    for root, dirs, files in os.walk(artifacts_dir):
        dirs.sort()
        for name in sorted(files):
            if name.endswith('.pkg'):
                pkg_files.append(os.path.join(root, name))
    if not pkg_files:
        raise ValueError(f"No .pkg files found in {artifacts_dir}")

    packages_by_dir = {}
    for pkg_path in pkg_files:
        sibling = os.path.join(os.path.dirname(pkg_path), 'packagesite_info.json')
        if os.path.exists(sibling):
            with open(sibling, "r") as f:
                info = json.load(f)
        else:
            try:
                info = _read_packagesite_info(pkg_path)
            except (tarfile.TarError, KeyError, json.JSONDecodeError, zstd.ZstdError, OSError, EOFError) as e:
                raise ValueError(f"{pkg_path}: could not read package manifest: {e}")
            info = _add_site_fields(info, pkg_path)
        abi_field = info.get('abi')
        if not abi_field:
            raise ValueError(f"{pkg_path}: no 'abi' in packagesite info")
        parts = abi_field.split(':')
        if len(parts) != 3 or parts[0] != 'FreeBSD':
            raise ValueError(f"{pkg_path}: unexpected abi {abi_field!r}")
        abi, arch = parts[1], parts[2]
        if abi not in declared_abis:
            raise ValueError(
                f"{pkg_path}: abi {abi} not declared in repo config {repo_config_path} "
                f"(pkg-repo.abi: {declared_abis})")
        if arch not in declared_archs:
            raise ValueError(
                f"{pkg_path}: arch {arch} not declared in repo config {repo_config_path} "
                f"(pkg-repo.arch: {declared_archs})")
        packages_by_dir.setdefault(f'FreeBSD:{abi}:{arch}', []).append((pkg_path, info))

    for repo_dir, packages in packages_by_dir.items():
        latest = os.path.join(output_dir, repo_dir, 'latest')
        target = os.path.join(latest, 'All')
        os.makedirs(target, exist_ok=True)
        with open(os.path.join(latest, 'packagesite.yaml'), 'w') as f:
            for pkg_path, info in packages:
                shutil.copy(pkg_path, os.path.join(target, os.path.basename(pkg_path)))
                f.write(json.dumps(info, separators=(',', ':')) + '\n')

    for entry in sorted(os.listdir(output_dir)):
        if not entry.startswith('FreeBSD:'):
            continue
        latest = os.path.join(output_dir, entry, 'latest')
        _create_packagesite_tzst(latest)
        with open(os.path.join(latest, 'meta.conf'), 'w') as f:
            json.dump(repo_config.get('meta-conf', {}), f, indent=2)
            f.write('\n')

    with open(os.path.join(output_dir, 'opnware.conf'), 'w') as f:
        f.write(f'opnware: {{\n'
                f'  url: "https://{owner}.github.io/{repo}/${{ABI}}/latest",\n'
                f'  priority: 5,\n'
                f'  enabled: yes\n'
                f'}}\n')

    _generate_index_tree(output_dir)
    with open(os.path.join(output_dir, 'robots.txt'), 'w') as f:
        f.write('User-agent: *\nDisallow: /\n')

def _read_packagesite_info(pkg_path):
    """Read the +COMPACT_MANIFEST out of a .pkg file."""
    with open(pkg_path, 'rb') as compressed_file:
        dctx = zstd.ZstdDecompressor()
        with dctx.stream_reader(compressed_file) as decompressed_stream:
            decompressed_data = io.BytesIO(decompressed_stream.read())
    with tarfile.open(fileobj=decompressed_data, mode='r:') as tar:
        return json.loads(tar.extractfile('+COMPACT_MANIFEST').read().decode())

def _add_site_fields(info, pkg_path):
    """Add the packagesite fields derived from the pkg file itself."""
    pkg_name = os.path.basename(pkg_path)
    info['path'] = f'All/{pkg_name}'
    info['repopath'] = f'All/{pkg_name}'
    info['sum'] = f'{_sha256sum(pkg_path)}'
    info['pkgsize'] = os.path.getsize(pkg_path)
    return info

def _create_packagesite_tzst(latest_dir):
    """Pack packagesite.yaml into packagesite.tzst, add the symlink, drop the source."""
    yaml_path = os.path.join(latest_dir, 'packagesite.yaml')
    tzst_path = os.path.join(latest_dir, 'packagesite.tzst')
    with open(tzst_path, 'wb') as fobj, zstd.ZstdCompressor().stream_writer(fobj) as zobj, \
            tarfile.open(fileobj=zobj, mode='w|', format=tarfile.PAX_FORMAT) as tar:
        info = _pinned_tarinfo(tar, yaml_path, 'packagesite.yaml')
        with open(yaml_path, 'rb') as f:
            tar.addfile(info, f)
    os.remove(yaml_path)
    link = os.path.join(latest_dir, 'packagesite.pkg')
    if os.path.lexists(link):
        os.unlink(link)
    os.symlink('./packagesite.tzst', link)

INDEX_HEADER = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Directory Listing</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f4f4f4;
        }
        a {
            text-decoration: none;
            color: #007bff;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
"""

INDEX_FOOTER = """</body>
</html>"""

def _readable_size(size):
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']:
        if size < 1024 or unit == 'PiB':
            return f'{size} {unit}' if unit == 'B' else f'{size:.1f} {unit}'
        size /= 1024

def _index_time(path):
    return datetime.datetime.fromtimestamp(os.stat(path).st_ctime, tz=datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S')

def _generate_index_tree(base_dir):
    """Write an index.html into every directory of base_dir."""
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        names = sorted(f for f in files if not f.startswith('.'))
        rel = os.path.relpath(root, base_dir)
        label = 'Index of /' if rel == '.' else f'Index of {rel}'
        with open(os.path.join(root, 'index.html'), 'w') as fh:
            fh.write(INDEX_HEADER)
            fh.write(f'<h1>{label}</h1>')
            fh.write('<table>')
            fh.write('<tr><th>Name</th><th>Size</th><th>Creation Date (UTC)</th></tr>')
            if rel != '.':
                fh.write("<tr><td><a href='../index.html'>..</a></td><td>-</td><td>-</td></tr>")
            fh.writelines(
                f"<tr><td><a href='./{d}/index.html'>{d}/</a></td><td>-</td><td>{_index_time(os.path.join(root, d))}</td></tr>"
                for d in dirs)
            for name in names:
                st = os.stat(os.path.join(root, name))
                fh.write(f"<tr><td><a href='{name}'>{name}</a></td><td>{_readable_size(st.st_size)}</td><td>{_index_time(os.path.join(root, name))}</td></tr>")
            fh.write('</table>')
            fh.write(INDEX_FOOTER)

def pack(config_path, abi, arch, payload_dir='pkg', output_dir='.'):
    """
    Pack a staged payload into a FreeBSD package.

    The payload is a FreeBSD staging root (the tree a build script fills,
    e.g. opt/opnware/pkgs/<name>/...). This performs the whole packing
    sequence: service file + rc.d link (if the spec declares a service),
    manifests, the zstd-compressed package, the packagesite info, and
    cleanup of its own staging.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
        payload_dir (str): Directory containing the staged payload. Defaults to 'pkg'.
        output_dir (str): Directory to output the package. Defaults to the current directory.
    """
    if not os.path.isdir(payload_dir):
        raise FileNotFoundError(f"Payload directory not found: {payload_dir}")
    with open(config_path, "r") as f:
        pkg_config = yaml.safe_load(f)
    name = pkg_config['pkg_manifest']['name'].lower()
    version = str(pkg_config['pkg_manifest']['version'])

    if pkg_config.get('pkg_service'):
        service_dir = os.path.join(payload_dir, 'opt/opnware/services', name)
        os.makedirs(service_dir, exist_ok=True)
        _create_service(config_path, service_dir)
        rc_dir = os.path.join(payload_dir, 'etc/rc.d')
        os.makedirs(rc_dir, exist_ok=True)
        rc_link = os.path.join(rc_dir, name)
        if os.path.lexists(rc_link):
            os.unlink(rc_link)
        os.symlink(f"../../opt/opnware/services/{name}/{name}", rc_link)

    _create_manifest(config_path, abi, arch, payload_dir, output_dir)
    pkg_file = os.path.join(output_dir, _pkg_filename(name, version))
    _create_pkg(pkg_file, output_dir, payload_dir)
    _create_packagesite_info(os.path.join(output_dir, '+COMPACT_MANIFEST'), output_dir)

    os.remove(os.path.join(output_dir, '+MANIFEST'))
    os.remove(os.path.join(output_dir, '+COMPACT_MANIFEST'))
    shutil.rmtree(payload_dir)

def _create_service(config_path, output_dir='.'):
    """
    Create service file.

    Args:
        config_path (str): Path to the config.yml file.
        output_dir (str): Directory to output the service file. Defaults to the current directory.
    """
    with open(config_path, "r") as f:
        pkg_config = yaml.safe_load(f)

    if pkg_config['pkg_service']:
        if pkg_config['pkg_service']['template']:
            env = Environment(
                loader=FileSystemLoader(os.path.join(os.path.dirname(config_path), '..', '..', 'service_templates')))
            template = env.get_template(pkg_config['pkg_service']['template'] + ".jinja")
            service = template.render(pkg_config['pkg_service']['vars'] | {'NAME': pkg_config['pkg_manifest']['name'].lower()})
        else:
            service = pkg_config['pkg_service']['service']
        file_name = os.path.join(output_dir, f"{pkg_config['pkg_manifest']['name'].lower()}")
        with open(file_name, 'w') as file:
            file.write(service)
        os.chmod(file_name, 0o775)

def redistribute_pkg(config_path, abi, arch, output_dir='.'):
    """
    Redistribute package.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
    """
    with open(config_path, "r") as f:
        pkg_config = yaml.safe_load(f)

    if pkg_config['redistribute']:
        dep = pkg_config['redistribute']
        version = dep["version"][f"FreeBSD-{abi}-{arch}"]
        pkg_name = _pkg_filename(dep['name'], version)
        pkg_url = f'{dep["repo"]}/FreeBSD:{abi}:{arch}/{dep["path"]}/{pkg_name}'
        print(f'Loading {pkg_name} from: {pkg_url}')
        _download_pkg(pkg_url, os.path.join(output_dir, pkg_name))
        _gen_pkgsite_info_from_pkg(os.path.join(output_dir, pkg_name), output_dir)

def _create_pkg(pkg_file, output_dir, payload_dir):
    """
    Create the zstd-compressed package.

    Mirrors the previous shell tail: +COMPACT_MANIFEST and +MANIFEST first,
    then payload files, then payload symlinks. Members are owned by uid/gid 0
    and names keep the leading '/' the historical GNU tar output had. mtime is
    pinned to 0 for reproducible builds.
    """
    files, links = [], []
    for root, dirs, names in os.walk(payload_dir):
        dirs.sort()
        for name in sorted(names):
            path = os.path.join(root, name)
            (links if os.path.islink(path) else files).append(path)

    members = [
        (os.path.join(output_dir, '+COMPACT_MANIFEST'), '+COMPACT_MANIFEST'),
        (os.path.join(output_dir, '+MANIFEST'), '+MANIFEST'),
    ]
    members += [(path, '/' + os.path.relpath(path, payload_dir)) for path in files]
    members += [(path, '/' + os.path.relpath(path, payload_dir)) for path in links]

    cctx = zstd.ZstdCompressor()
    with open(pkg_file, 'wb') as fobj, cctx.stream_writer(fobj) as zobj, \
            tarfile.open(fileobj=zobj, mode='w|', format=tarfile.PAX_FORMAT) as tar:
        for path, arcname in members:
            info = _pinned_tarinfo(tar, path, arcname)
            if info.isfile():
                with open(path, 'rb') as f:
                    tar.addfile(info, f)
            else:
                tar.addfile(info)

def _sha256sum(file):
    """
    Compute the SHA-256 checksum of a file.

    Args:
        file (str): Path to the file.

    Returns:
        str: SHA-256 checksum of the file.
    """
    with open(file, 'rb', buffering=0) as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def _folder_size(folder):
    """
    Calculate the total size of a folder.

    Args:
        folder (str): Path to the folder.

    Returns:
        int: Total size of the folder in bytes.
    """
    total_size = 0
    for dirpath, _, filenames in os.walk(folder):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size

def _download_pkg(url, file):
    """
    Download a package from a URL.

    Args:
        url (str): URL of the package.
        file (str): Path to save the downloaded package.
    """
    with urllib.request.urlopen(url, timeout=30) as req, open(file, 'wb') as f:
        f.write(req.read())

def _gen_pkgsite_info_from_pkg(pkg, output_dir):
    """
    Generate package site information from a package file.

    Args:
        pkg (str): Package file.
        output_dir (str): Directory to output the packagesite info file.
    """
    pkg_info = _add_site_fields(_read_packagesite_info(pkg), pkg)
    with open(os.path.join(output_dir, "packagesite_info.json"), "w") as f:
        json.dump(pkg_info, f, separators=(',', ':'))

def main():
    """
    Main function to parse command-line arguments and execute corresponding functions.
    """
    parser = argparse.ArgumentParser(description='FreeBSD Custom Package Repository CLI')
    subparsers = parser.add_subparsers(dest='command')

    parser_pack = subparsers.add_parser('pack', help='Pack a staged payload into a FreeBSD package')
    parser_pack.add_argument('config_path', help='Path to the config.yml file')
    parser_pack.add_argument('--abi', required=True, help='ABI')
    parser_pack.add_argument('--arch', required=True, help='Architecture')
    parser_pack.add_argument('--payload-dir', required=False, default='pkg',
                             help='Directory containing the staged payload (default: pkg)')
    parser_pack.add_argument('--output-dir', required=False, default='.',
                             help='Directory to output the package (default: current directory)')

    parser_redistribute_pkg = subparsers.add_parser('redistribute-pkg', help='Redistribute package')
    parser_redistribute_pkg.add_argument('config_path', help='Path to the config.yml file')
    parser_redistribute_pkg.add_argument('--abi', required=True, help='ABI')
    parser_redistribute_pkg.add_argument('--arch', required=True, help='Architecture')
    parser_redistribute_pkg.add_argument('--output-dir', required=False, default='.',
                                         help='Directory to output the package & packagesite info file  (default: current directory)')

    parser_assemble_repo = subparsers.add_parser('assemble-repo', help='Assemble the published repo tree from built packages')
    parser_assemble_repo.add_argument('artifacts_dir', help='Directory containing .pkg files and their packagesite_info.json')
    parser_assemble_repo.add_argument('repo_config', help='Path to the repo-level config.yml')
    parser_assemble_repo.add_argument('--owner', required=True, help='GitHub owner (used in the opnware.conf URL)')
    parser_assemble_repo.add_argument('--repo', required=True, help='GitHub repo name (used in the opnware.conf URL)')
    parser_assemble_repo.add_argument('--output-dir', required=False, default='pages',
                                      help='Directory to output the repo tree (default: pages)')

    args = parser.parse_args()

    if args.command == 'pack':
        pack(args.config_path, args.abi, args.arch, args.payload_dir, args.output_dir)
    elif args.command == 'redistribute-pkg':
        redistribute_pkg(args.config_path, args.abi, args.arch, args.output_dir)
    elif args.command == 'assemble-repo':
        assemble_repo(args.artifacts_dir, args.repo_config, args.owner, args.repo, args.output_dir)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
