import argparse
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
            info = tar.gettarinfo(path)
            info.name = arcname
            info.uid = 0
            info.gid = 0
            info.uname = ''
            info.gname = ''
            info.mtime = 0
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
    with open(pkg, 'rb') as compressed_file:
        pkg_name = os.path.basename(pkg)
        dctx = zstd.ZstdDecompressor()
        with dctx.stream_reader(compressed_file) as decompressed_stream:
            decompressed_data = io.BytesIO(decompressed_stream.read())
        with tarfile.open(fileobj=decompressed_data, mode='r:') as tar, \
                open(os.path.join(output_dir, "packagesite_info.json"), "w") as f:
            pkg_info = json.loads(tar.extractfile('+COMPACT_MANIFEST').read().decode())
            pkg_info['path'] = f'All/{pkg_name}'
            pkg_info['repopath'] = f'All/{pkg_name}'
            pkg_info['sum'] = f'{_sha256sum(pkg_name)}'
            pkg_info['pkgsize'] = os.path.getsize(pkg_name)
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

    args = parser.parse_args()

    if args.command == 'pack':
        pack(args.config_path, args.abi, args.arch, args.payload_dir, args.output_dir)
    elif args.command == 'redistribute-pkg':
        redistribute_pkg(args.config_path, args.abi, args.arch, args.output_dir)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
