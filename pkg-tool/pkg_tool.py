import argparse
import datetime
import hashlib
import io
import json
import logging
import os
import re
import shutil
import sys
import tarfile
import urllib.request
from pathlib import Path

import requests
import yaml
import zstandard as zstd
from requests.compat import quote_plus, urljoin, urlparse

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s', stream=sys.stderr)

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

def _create_manifest(config_path, abi, arch, payload_dir, output_dir='.', spec=None):
    """
    Create manifest files from a staged payload.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
        payload_dir (str): Directory containing the staged payload.
        output_dir (str): Directory to output the manifest files. Defaults to the current directory.
        spec (dict): Pre-validated spec; re-read from config_path when omitted.
    """
    if not os.path.isdir(payload_dir):
        raise FileNotFoundError(f"Payload directory not found: {payload_dir}")
    if spec is None:
        with open(config_path, "r") as f:
            spec = yaml.safe_load(f)
    pkg_config = spec
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

def _validate_spec(spec, source):
    """Validate a package spec, raising (ValueError|TypeError) with key-path errors."""
    if not isinstance(spec, dict):
        raise TypeError(f"{source}: spec is not a mapping")
    pkg_manifest = spec.get('pkg_manifest')
    redistribute = spec.get('redistribute')
    if pkg_manifest is None and redistribute is None:
        raise ValueError(f"{source}: neither pkg_manifest nor redistribute present")
    plugin = spec.get('plugin')
    if plugin is not None and redistribute is not None:
        raise ValueError(f"{source}: plugin specs cannot be redistributed")
    if pkg_manifest is not None and redistribute is not None:
        raise ValueError(f"{source}: both pkg_manifest and redistribute present")
    if spec.get('pkg_service'):
        raise ValueError(f"{source}: pkg_service is retired — plain packages ship no service/rc.d machinery (ticket #205)")
    if plugin is not None:
        if pkg_manifest is None:
            raise ValueError(f"{source}: plugin requires pkg_manifest")
        if not isinstance(plugin, dict):
            raise TypeError(f"{source}: plugin is not a mapping")
        if not plugin.get('opnsense_version'):
            raise ValueError(f"{source}: plugin.opnsense_version required")
        if not isinstance(plugin['opnsense_version'], str):
            raise TypeError(f"{source}: plugin.opnsense_version must be a string")
        conflicts = plugin.get('conflicts')
        if conflicts is not None and (
                not isinstance(conflicts, list) or not all(isinstance(c, str) for c in conflicts)):
            raise TypeError(f"{source}: plugin.conflicts must be a list of strings")
        tier = plugin.get('tier')
        if tier is not None and not isinstance(tier, int):
            raise TypeError(f"{source}: plugin.tier must be an integer")
        if isinstance(pkg_manifest.get('name'), str) and pkg_manifest['name'].startswith('os-'):
            raise ValueError(f"{source}: plugin name must be the short name, not os- prefixed")
    build_config = spec.get('build_config')
    if not isinstance(build_config, dict):
        raise TypeError(f"{source}: build_config is not a mapping")
    if not isinstance(build_config.get('include'), dict):
        raise TypeError(f"{source}: build_config.include must be a mapping")
    content = spec.get('content')
    if content is not None:
        if not isinstance(content, dict):
            raise TypeError(f"{source}: content is not a mapping")
        if not content.get('repo') or not isinstance(content['repo'], str) \
                or 'github.com' not in content['repo']:
            raise ValueError(f"{source}: content.repo must be a github.com URL")
        if not content.get('version'):
            raise ValueError(f"{source}: content.version required")
        if isinstance(content['version'], (dict, list)):
            raise TypeError(f"{source}: content.version must be a scalar")
    if 'vendor' in spec:
        vendor = spec['vendor']
        if not isinstance(vendor, dict) or not vendor.get('npm') or not isinstance(vendor['npm'], str):
            raise ValueError(f"{source}: vendor.npm required (the npm package name)")
    if pkg_manifest is not None:
        if not isinstance(pkg_manifest, dict):
            raise TypeError(f"{source}: pkg_manifest is not a mapping")
        for key in ('name', 'version', 'origin'):
            if key not in pkg_manifest:
                raise ValueError(f"{source}: pkg_manifest.{key} missing")
        for key in ('name', 'origin'):
            if isinstance(pkg_manifest[key], (dict, list)):
                raise TypeError(f"{source}: pkg_manifest.{key} must be a scalar")
        if isinstance(pkg_manifest['version'], (dict, list)):
            raise TypeError(f"{source}: pkg_manifest.version must be a scalar")
        src_repo = build_config.get('src_repo')
        if src_repo and not isinstance(src_repo, str):
            raise TypeError(f"{source}: build_config.src_repo must be a string")
        if src_repo and 'github.com' not in src_repo and 'sf.net' not in src_repo:
            raise ValueError(f"{source}: build_config.src_repo: unsupported source {src_repo!r}")
    if redistribute is not None:
        if not isinstance(redistribute, dict):
            raise TypeError(f"{source}: redistribute is not a mapping")
        if 'name' not in redistribute:
            raise ValueError(f"{source}: redistribute.name missing")
        if isinstance(redistribute['name'], (dict, list)):
            raise TypeError(f"{source}: redistribute.name must be a scalar")
        version = redistribute.get('version')
        if not isinstance(version, dict) or not version:
            raise TypeError(f"{source}: redistribute.version must be a non-empty mapping")
        for abi_arch in version:
            if not re.match(r'^FreeBSD-\d+-(amd64|aarch64|arm64|i386|x86_64)$', str(abi_arch)):
                raise ValueError(f"{source}: redistribute.version.{abi_arch}: unexpected ABI/arch key")

def _validate_repo_config(config, source):
    """Validate the repo-level config, raising TypeError with key-path errors."""
    if not isinstance(config, dict):
        raise TypeError(f"{source}: repo config is not a mapping")
    pkg_repo = config.get('pkg-repo')
    if not isinstance(pkg_repo, dict) or not pkg_repo.get('abi') or not pkg_repo.get('arch'):
        raise TypeError(f"{source}: pkg-repo.abi and pkg-repo.arch are required")

def _load_spec(config_path):
    with open(config_path) as f:
        spec = yaml.safe_load(f)
    _validate_spec(spec, config_path)
    return spec

def _load_repo_config(config_path):
    with open(config_path) as f:
        config = yaml.safe_load(f)
    _validate_repo_config(config, config_path)
    return config

def dump(config_path, key_path):
    """Print one scalar from a validated package spec."""
    spec = _load_spec(config_path)
    value = spec
    for part in key_path.split('.'):
        if not isinstance(value, dict) or part not in value:
            raise ValueError(f"{config_path}: no '{key_path}' in spec")
        value = value[part]
    if isinstance(value, (dict, list)):
        raise TypeError(f"{config_path}: '{key_path}' is not a scalar")
    return str(value)

def build_matrix(packages=None, pkgs_dir='pkgs', repo_config='config.yml'):
    """
    Emit the build matrix the CI consumes.

    Args:
        packages (list): Package names to include; None walks pkgs_dir for build.sh dirs.
        pkgs_dir (str): Directory containing the package specs. Defaults to 'pkgs'.
        repo_config (str): Path to the repo-level config.yml. Defaults to 'config.yml'.
    """
    if packages:
        expanded = []
        for pkg in packages:
            expanded += pkg.strip().split(' ')
        packages = expanded
    else:
        packages = []
        for root, _, files in os.walk(pkgs_dir):
            if 'build.sh' in files:
                packages.append(os.path.basename(root))
        packages.sort()

    config = _load_repo_config(repo_config)
    includes = []
    for pkg in packages:
        config_path = os.path.join(pkgs_dir, pkg, 'config.yml')
        if os.path.exists(config_path):
            spec = _load_spec(config_path)
            include = dict(spec['build_config']['include'])
            include['pkg_name'] = pkg
            includes.append(include)
    return {
        'pkg_name': packages,
        'arch': config['pkg-repo']['arch'],
        'abi': config['pkg-repo']['abi'],
        'include': includes,
    }

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
    repo_config = _load_repo_config(repo_config_path)
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
        if arch == '*':
            # architecture-independent meta-packages (e.g. lang/go) are valid
            # for every arch the repo declares; land them in each slot
            archs = declared_archs
        elif arch not in declared_archs:
            raise ValueError(
                f"{pkg_path}: arch {arch} not declared in repo config {repo_config_path} "
                f"(pkg-repo.arch: {declared_archs})")
        else:
            archs = [arch]
        for slot_arch in archs:
            packages_by_dir.setdefault(f'FreeBSD:{abi}:{slot_arch}', []).append((pkg_path, info))

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

def _plugin_hooks(payload_dir, pkg_name):
    """Derive the pkg lifecycle scripts from what the plugin payload ships.

    Mirrors the opnsense/plugins framework Templates: actions.d -> configd
    restart, MVC models -> run_migrations, service templates -> template
    reload, plugins.inc.d -> rc.configure_plugins. Additionally self-registers
    the plugin (system.firmware.plugins) on install and unregisters it on
    deinstall, so Firmware -> Plugins shows the plugin as configured instead of
    'misconfigured' when installed directly with pkg (the firmware UI normally
    runs register.php itself).
    """
    base = os.path.join(payload_dir, 'usr/local/opnsense')
    post, deinstall = [], []
    if os.path.isdir(os.path.join(base, 'service/conf/actions.d')):
        post.append('if [ -f /usr/local/etc/rc.d/configd ]; then /usr/local/etc/rc.d/configd restart; fi')
    models_dir = os.path.join(base, 'mvc/app/models/OPNsense')
    if os.path.isdir(models_dir):
        for module in sorted(os.listdir(models_dir)):
            post.append(f'if [ -f /usr/local/opnsense/mvc/script/run_migrations.php ]; '
                        f'then /usr/local/opnsense/mvc/script/run_migrations.php OPNsense/{module}; fi')
    tpl_dir = os.path.join(base, 'service/templates/OPNsense')
    if os.path.isdir(tpl_dir):
        for module in sorted(os.listdir(tpl_dir)):
            post.append(f'if [ -f /usr/local/sbin/configctl ]; then echo -n "Reloading template OPNsense/{module}: "; '
                        f'/usr/local/sbin/configctl template reload OPNsense/{module}; fi')
    if os.path.isdir(os.path.join(payload_dir, 'usr/local/etc/inc/plugins.inc.d')):
        post.append('if [ -f /usr/local/etc/rc.configure_plugins ]; then echo "Reloading plugin configuration"; '
                    '/usr/local/etc/rc.configure_plugins post-install; fi')
        deinstall.append('if [ -f /usr/local/etc/rc.configure_plugins ]; then echo "Reloading plugin configuration"; '
                         '/usr/local/etc/rc.configure_plugins post-deinstall; fi')
    register = '/usr/local/opnsense/scripts/firmware/register.php'
    if os.path.isdir(os.path.join(payload_dir, 'usr/local/opnsense/version')):
        post.append(f'if [ -f {register} ]; then {register} install {pkg_name}; fi')
        deinstall.append(f'if [ -f {register} ]; then {register} remove {pkg_name}; fi')
    scripts = {}
    if post:
        scripts['post-install'] = '\n'.join(post) + '\n'
    if deinstall:
        scripts['post-deinstall'] = '\n'.join(deinstall) + '\n'
    return scripts


def _plugin_package(payload_dir, plugin, manifest, arch, version):
    """Stage the OPNsense version annotation into the payload; return
    (os-prefixed package name, product annotation, lifecycle scripts)."""
    name = manifest['name']
    pkg_name = f"os-{name}"
    annotation = {
        'product_abi': str(plugin.get('opnsense_version', '')),
        'product_arch': str(arch),
        'product_conflicts': ' '.join(str(c) for c in plugin.get('conflicts', [])),
        'product_email': str(manifest.get('maintainer', '')),
        'product_hash': str(plugin.get('hash', '')),
        'product_id': pkg_name,
        'product_name': name,
        'product_tier': str(plugin.get('tier', 3)),
        'product_version': str(version),
        'product_website': str(manifest.get('www', '')),
    }
    ver_dir = os.path.join(payload_dir, 'usr/local/opnsense/version')
    os.makedirs(ver_dir, exist_ok=True)
    with open(os.path.join(ver_dir, name), 'w') as f:
        json.dump(annotation, f, indent=2)
    return pkg_name, annotation, _plugin_hooks(payload_dir, pkg_name)


def _stage_licenses(payload_dir, pkg_name, version, licenses):
    """Copy license texts into the payload's /usr/local/share/licenses dir.

    Firmware -> Packages reads licenses from
    /usr/local/share/licenses/<pkg>-<version>/<LICENSE_ID> (license.sh), so
    every package must ship its license files there or the UI reports "the
    package does not have an associated license file".

    Sources are the staged doc LICENSE files. For a single-license package the
    bare /usr/local/share/doc/<dir>/LICENSE is used; multi-license packages
    stage explicit per-license files (LICENSE.<ID>) next to it so pkg-tool
    can map each declared ID to its text.
    """
    if not licenses:
        return
    doc_root = os.path.join(payload_dir, 'usr/local/share/doc')
    if not os.path.isdir(doc_root):
        return
    explicit = {}
    generic = []
    for root, _, files in os.walk(doc_root):
        for f in files:
            if f == 'LICENSE':
                generic.append(os.path.join(root, f))
            elif f.startswith('LICENSE.'):
                explicit[f[len('LICENSE.'):]] = os.path.join(root, f)

    lic_dir = os.path.join(payload_dir, 'usr/local/share/licenses', f'{pkg_name}-{version}')
    os.makedirs(lic_dir, exist_ok=True)
    for lic_id in licenses:
        source = explicit.get(lic_id)
        if source is None and len(licenses) == 1 and len(generic) == 1:
            # Single-license package: the bare staged LICENSE is the text.
            source = generic[0]
        if source and os.path.isfile(source):
            target = os.path.join(lic_dir, lic_id)
            shutil.copyfile(source, target)
            os.chmod(target, 0o644)
        else:
            print(f"warning: no staged license text found for {pkg_name} license {lic_id}; "
                  f"Firmware -> Packages will report a missing license file")


def pack(config_path, abi, arch, payload_dir='pkg', output_dir='.'):
    """
    Pack a staged payload into a FreeBSD package.

    The payload is a FreeBSD staging root (the tree a build script fills,
    e.g. usr/local/...). For plugin specs the package is packed with the
    os- prefix, the OPNsense version annotation and auto-derived lifecycle
    hooks. This performs the whole packing sequence: manifests, the
    zstd-compressed package, the packagesite info, and cleanup of its own
    staging.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
        payload_dir (str): Directory containing the staged payload. Defaults to 'pkg'.
        output_dir (str): Directory to output the package. Defaults to the current directory.
    """
    if not os.path.isdir(payload_dir):
        raise FileNotFoundError(f"Payload directory not found: {payload_dir}")
    pkg_config = _load_spec(config_path)
    manifest = pkg_config['pkg_manifest']
    version = str(manifest['version'])

    if pkg_config.get('plugin'):
        name, annotation, scripts = _plugin_package(
            payload_dir, pkg_config['plugin'], manifest, arch, version)
        manifest['name'] = name
        manifest['origin'] = f"opnware/{name}"
        manifest['scripts'] = scripts
        manifest['annotations'] = annotation
    else:
        name = manifest['name'].lower()

    _stage_licenses(payload_dir, name, version, manifest.get('licenses', []))
    _create_manifest(config_path, abi, arch, payload_dir, output_dir, spec=pkg_config)
    pkg_file = os.path.join(output_dir, _pkg_filename(name, version))
    _create_pkg(pkg_file, output_dir, payload_dir)
    _create_packagesite_info(os.path.join(output_dir, '+COMPACT_MANIFEST'), output_dir)

    os.remove(os.path.join(output_dir, '+MANIFEST'))
    os.remove(os.path.join(output_dir, '+COMPACT_MANIFEST'))
    shutil.rmtree(payload_dir)

def redistribute_pkg(config_path, abi, arch, output_dir='.'):
    """
    Redistribute package.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
    """
    pkg_config = _load_spec(config_path)

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

def _replace_scalar(line, new_value):
    """Rewrite a scalar on a version line, preserving the original quoting."""
    m = re.match(r'^(\s*[^:]+:\s*)(["\']?)(.*?)(["\']?)\s*$', line)
    if not m:
        raise ValueError(f"cannot rewrite version line: {line!r}")
    prefix, open_q, _, close_q = m.groups()
    quote = open_q or close_q or ''
    return f"{prefix}{quote}{new_value}{quote}\n"

def _replace_scalar_in_section(content, section, key, new_value):
    """Rewrite the scalar of `key` inside the given top-level section."""
    out = []
    in_section = False
    replaced = False
    for line in content.splitlines(keepends=True):
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if indent == 0 and stripped and not stripped.startswith('#'):
            in_section = stripped.startswith(f'{section}:')
        elif in_section and stripped.startswith(f'{key}:'):
            out.append(_replace_scalar(line, new_value))
            in_section = False
            replaced = True
            continue
        out.append(line)
    if not replaced:
        raise ValueError(f"no '{key}' line found under the '{section}' section")
    return ''.join(out)

def _replace_scalar_in_section_line(content, section, leaf, new_value):
    """Rewrite the `leaf:` line inside the given top-level section, preserving quoting."""
    in_section = False
    lines = content.splitlines(keepends=True)
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if indent == 0 and stripped and not stripped.startswith('#'):
            if in_section:
                break
            in_section = stripped.startswith(f'{section}:')
        elif in_section and stripped.startswith(f'{leaf}:'):
            lines[i] = _replace_scalar(line, new_value)
            return ''.join(lines)
    raise ValueError(f"no '{leaf}' line found under the '{section}' section")

def bump(pkg, version=None, abi_arch=None):
    """
    Write a version back into a package spec, preserving file formatting.

    Args:
        pkg (str): Package name (a directory under pkgs/).
        version (str): New version for build specs, or per-abi_arch for redistribute specs.
        abi_arch (str): ABI/arch key (e.g. FreeBSD-15-amd64) for redistribute specs.
    """
    config_path = os.path.join('pkgs', pkg, 'config.yml')
    with open(config_path) as f:
        content = f.read()
    if version is None:
        raise ValueError("--version is required")
    spec = _load_spec(config_path)
    if spec.get('content'):
        content = _replace_scalar_in_section_line(content, 'content', 'version', version)
        # A content change rev-bumps the package version (FreeBSD _REVISION)
        # so an updated bundle is visible as a new package revision without
        # changing the plugin's own version base.
        manifest_version = str(spec['pkg_manifest']['version'])
        m = re.match(r'^(.*?)(?:_(\d+))?$', manifest_version)
        base, revision = m.group(1), int(m.group(2) or 0) + 1
        content = _replace_scalar_in_section(
            content, 'pkg_manifest', 'version', f'{base}_{revision}')
    elif spec.get('redistribute'):
        if abi_arch is None:
            raise ValueError(f"{config_path}: redistribute specs need --abi-arch")
        if abi_arch not in spec['redistribute'].get('version', {}):
            raise ValueError(f"{config_path}: no version entry for {abi_arch}")
        content = _replace_scalar_in_section_line(content, 'redistribute', abi_arch, version)
    else:
        content = _replace_scalar_in_section(content, 'pkg_manifest', 'version', version)
    with open(config_path, 'w') as f:
        f.write(content)

packagesite_cache = {}

def _multi_urljoin(*parts):
    return urljoin(parts[0], "/".join(quote_plus(part.strip("/"), safe="/") for part in parts[1:]))

def _detect_pkg_comp_fmt(url_base, abi_arch, path):
    meta_conf_url = _multi_urljoin(url_base, abi_arch.replace('-', ':'), path, "meta.conf")
    response = requests.get(meta_conf_url)
    if response.status_code != 200:
        raise ValueError(f"failed to fetch {meta_conf_url}: HTTP {response.status_code}")
    match = re.search(r'packing_format\s*=\s*"?([^"]+)"?', response.text)
    if not match:
        raise ValueError(f"no packing_format found in {meta_conf_url}")
    return match.group(1)

def _extract_packagesite(pkgsite_data, compression_format):
    if compression_format == "tzst":
        with io.BytesIO(pkgsite_data) as f:
            dctx = zstd.ZstdDecompressor()
            with dctx.stream_reader(f) as s:
                data = io.BytesIO(s.read())
        with tarfile.open(fileobj=data, mode='r:') as tar:
            content = tar.extractfile('packagesite.yaml').read()
    else:
        with tarfile.open(fileobj=io.BytesIO(pkgsite_data), mode=f'r:{compression_format[1:]}') as tar:
            content = tar.extractfile('packagesite.yaml').read()
    return [json.loads(line) for line in io.StringIO(content.decode()).readlines()]

def _load_packagesite(url_base, abi_arch, path):
    domain = urlparse(url_base).netloc.replace('.', '-')
    key = f"{domain}-{abi_arch}-{path}"
    if key in packagesite_cache:
        return packagesite_cache[key]
    url = _multi_urljoin(url_base, abi_arch.replace('-', ':'), path, "packagesite.pkg")
    response = requests.get(url)
    if response.status_code != 200:
        raise ValueError(f"failed to download {url}: HTTP {response.status_code}")
    compression_format = _detect_pkg_comp_fmt(url_base, abi_arch, path)
    packagesite_cache[key] = _extract_packagesite(response.content, compression_format)
    return packagesite_cache[key]

def _bsd_latest_version(pkg_name, config, abi_arch):
    url_base = config.get('redistribute', {}).get('repo', '')
    path = config.get('redistribute', {}).get('path', '').split('/')[0]
    for package in _load_packagesite(url_base, abi_arch, path):
        if package.get('name') == pkg_name:
            return package.get('version')
    raise ValueError(f"{pkg_name} not found in packagesite from {url_base}")

def _gh_latest_version(src_repo, token=None):
    match = re.search(r'https://github.com/([^/]+/[^/]+)', src_repo)
    if not match:
        raise ValueError(f"could not parse GitHub repository from {src_repo}")
    headers = {'Authorization': f'token {token}'} if token else {}
    response = requests.get(f"https://api.github.com/repos/{match.group(1)}/releases/latest", headers=headers)
    if response.status_code != 200:
        raise ValueError(f"failed to get release info from GitHub API: HTTP {response.status_code}")
    remote_version = str(response.json().get('tag_name', '')).lstrip('v')
    if not remote_version:
        raise ValueError(f"no release found for {src_repo}")
    return remote_version

def _sf_latest_version(src_repo):
    match = re.search(r'https://git.code.sf.net/p/([^/]+/code)', src_repo)
    if not match:
        raise ValueError(f"could not parse Sourceforge repository from {src_repo}")
    sf_repo = match.group(1).split('/')[0]
    response = requests.get(f"https://sourceforge.net/projects/{sf_repo}/best_release.json")
    if response.status_code != 200:
        raise ValueError(f"failed to get release info from SourceForge: HTTP {response.status_code}")
    parts = response.json().get('release', {}).get('filename', '').split('/')
    if len(parts) < 3:
        raise ValueError(f"unexpected SourceForge release filename: {parts!r}")
    return parts[-2]

def _npm_latest_version(package):
    """The latest version of an npm package (e.g. monaco-editor)."""
    response = requests.get(f"https://registry.npmjs.org/{quote_plus(package)}/latest")
    if response.status_code != 200:
        raise ValueError(f"failed to get release info from npm registry: HTTP {response.status_code}")
    remote = str(response.json().get('version', ''))
    if not remote:
        raise ValueError(f"no version found for npm package {package}")
    return remote

def check_updates(pkgs_dir='pkgs'):
    """
    Check all package specs for newer versions.

    Returns the update matrix: {'pkg': [...], 'include': [{pkg, abi_arch, version}, ...]}.
    Sources are adapters: FreeBSD packagesite (redistribute specs), GitHub releases
    and SourceForge (build specs with a src_repo).
    """
    matrix = {'pkg': [], 'include': []}
    for config_file in sorted(Path(pkgs_dir).glob('*/config.yml')):
        pkg_name = config_file.parent.name
        config = _load_spec(config_file)
        if config.get('vendor'):
            # Vendored npm assets (e.g. the shared editor) are checked against
            # the npm registry. The 'vendor' abi_arch routes the workflow to
            # the refresh script (which re-vendors AND bumps — a bare bump
            # would fail the build guard) and skips auto-merge.
            remote = _npm_latest_version(config['vendor']['npm'])
            local = str(config.get('pkg_manifest', {}).get('version'))
            # A FreeBSD revision suffix (_N) marks package-only changes and is
            # not a version difference — strip it before comparing, mirroring
            # the guard in pkgs/*/build.sh, so a vendored npm release equal to
            # the base version does not emit a nightly update.
            local_base = re.sub(r'_[0-9]+$', '', local)
            if str(remote) != local_base:
                matrix['pkg'].append(pkg_name)
                matrix['include'].append({'pkg': pkg_name, 'abi_arch': 'vendor', 'version': remote})
            continue
        if config.get('content'):
            # Bundled content (e.g. the Homer dashboard inside os-homer)
            # follows the upstream repo releases — checked even though the
            # spec is a plugin. The 'content' abi_arch routes bump to the
            # content.version line and rev-bumps the plugin package version.
            remote = _gh_latest_version(config['content']['repo'], os.environ.get('GITHUB_TOKEN'))
            local = str(config['content']['version'])
            if str(remote) != local:
                matrix['pkg'].append(pkg_name)
                matrix['include'].append({'pkg': pkg_name, 'abi_arch': 'content', 'version': remote})
            continue
        if config.get('plugin'):
            continue
        if config.get('redistribute'):
            for abi_arch, local in config['redistribute']['version'].items():
                remote = _bsd_latest_version(pkg_name, config, abi_arch)
                if str(remote) != str(local):
                    matrix['pkg'].append(pkg_name)
                    matrix['include'].append({'pkg': pkg_name, 'abi_arch': abi_arch, 'version': remote})
        else:
            src_repo = config.get('build_config', {}).get('src_repo', '')
            local = str(config.get('pkg_manifest', {}).get('version'))
            if 'github.com' in src_repo:
                remote = _gh_latest_version(src_repo, os.environ.get('GITHUB_TOKEN'))
            elif 'sf.net' in src_repo:
                remote = _sf_latest_version(src_repo)
            else:
                continue  # static asset packages (e.g. the shared editor) have no remote version source
            # A FreeBSD revision suffix (_N) marks package-only changes and is
            # not a version difference — strip it before comparing, mirroring
            # the guard in pkgs/*/build.sh and the vendor branch above.
            local_base = re.sub(r'_[0-9]+$', '', local)
            if str(remote) != local_base:
                matrix['pkg'].append(pkg_name)
                matrix['include'].append({'pkg': pkg_name, 'abi_arch': 'ALL', 'version': remote})
    return matrix

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

    parser_check_updates = subparsers.add_parser('check-updates', help='Check all package specs for newer versions')
    parser_check_updates.add_argument('--pkgs-dir', required=False, default='pkgs',
                                      help='Directory containing the package specs (default: pkgs)')

    parser_bump = subparsers.add_parser('bump', help='Write a version back into a package spec')
    parser_bump.add_argument('pkg', help='Package name (a directory under pkgs/)')
    parser_bump.add_argument('--version', required=False, help='New version')
    parser_bump.add_argument('--abi-arch', required=False,
                             help='ABI/arch key for redistribute specs (e.g. FreeBSD-15-amd64)')

    parser_dump = subparsers.add_parser('dump', help='Print one scalar from a validated package spec')
    parser_dump.add_argument('config_path', help='Path to the config.yml file')
    parser_dump.add_argument('key_path', help='Dotted key path, e.g. pkg_manifest.version')

    parser_build_matrix = subparsers.add_parser('build-matrix', help='Emit the build matrix JSON')
    parser_build_matrix.add_argument('pkgs', nargs='*', help='Packages to include (default: all with a build.sh)')

    args = parser.parse_args()

    try:
        if args.command == 'pack':
            pack(args.config_path, args.abi, args.arch, args.payload_dir, args.output_dir)
        elif args.command == 'redistribute-pkg':
            redistribute_pkg(args.config_path, args.abi, args.arch, args.output_dir)
        elif args.command == 'assemble-repo':
            assemble_repo(args.artifacts_dir, args.repo_config, args.owner, args.repo, args.output_dir)
        elif args.command == 'check-updates':
            matrix = check_updates(args.pkgs_dir)
            if matrix['pkg']:
                print(json.dumps(matrix))
        elif args.command == 'bump':
            bump(args.pkg, args.version, args.abi_arch)
        elif args.command == 'dump':
            print(dump(args.config_path, args.key_path))
        elif args.command == 'build-matrix':
            print(json.dumps(build_matrix(args.pkgs), separators=(',', ':')))
        else:
            parser.print_help()
    except (TypeError, ValueError, FileNotFoundError, KeyError) as e:
        logging.getLogger(__name__).error(str(e))
        sys.exit(1)

if __name__ == '__main__':
    main()
