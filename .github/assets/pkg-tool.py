import os
import json
import yaml
import hashlib
import urllib.request
import tarfile
import zstandard as zstd
import io
from jinja2 import Environment, FileSystemLoader
import argparse

"""
FreeBSD Custom Package Repository CLI

This module provides functionality to create manifest files, package site information,
service files, and to redistribute packages for FreeBSD custom package repositories.

Usage:
    pkg-tool <command> [options]

Commands:
    create-manifest          Create manifest files.
    create-packagesite-info  Create package site info.
    create-service           Create service file.
    redistribute-pkg         Redistribute package.

Examples:
    pkg-tool create-manifest ./config.yml --abi 14 --arch amd64
    pkg-tool create-packagesite-info ./+COMPACT_MANIFEST
    pkg-tool create-service ./config.yml
    pkg-tool redistribute-pkg ./config.yml --abi 14 --arch amd64
"""

def create_manifest(config_path, abi, arch, output_dir='.'):
    """
    Create manifest files.

    Args:
        config_path (str): Path to the config.yml file.
        abi (str): ABI string.
        arch (str): Architecture string.
        output_dir (str): Directory to output the manifest files. Defaults to the current directory.
    """
    with open(config_path, "r") as f:
        pkg_config = yaml.safe_load(f)
    manifest = pkg_config["pkg_manifest"]
    manifest['version'] = str(manifest['version'])
    manifest['abi'] = f'FreeBSD:{abi}:{arch}'
    manifest['arch'] = manifest['abi'].lower().replace('amd64', 'x86:64')
    manifest['flatsize'] = _folder_size(".")

    manifest['files'] = {}
    for root, _, files in os.walk('.'):
        if files:
            for file in files:
                file_path = os.path.join(root, file)
                manifest['files'][f'{os.sep}{os.path.relpath(file_path, "./pkg")}'] = _sha256sum(file_path)

    with open(os.path.join(output_dir, '+MANIFEST'), "w") as f:
        json.dump(manifest, f, separators=(',', ':'))

    manifest.pop('files', None)
    manifest.pop('scripts', None)

    with open(os.path.join(output_dir, '+COMPACT_MANIFEST'), "w") as f:
        json.dump(manifest, f, separators=(',', ':'))

def create_packagesite_info(compact_manifest_path, output_dir='.'):
    """
    Create package site information file.

    Args:
        compact_manifest_path (str): Path to the +COMPACT_MANIFEST file.
        output_dir (str): Directory to output the packagesite info file. Defaults to the current directory.
    """
    with open(compact_manifest_path, "r") as f:
        pkg_info = json.load(f)

    pkg = f'{pkg_info["name"]}-{pkg_info["version"]}.pkg'

    pkg_info['path'] = f'All/{pkg}'
    pkg_info['repopath'] = f'All/{pkg}'
    pkg_info['sum'] = f'{_sha256sum(pkg)}'
    pkg_info['pkgsize'] = os.path.getsize(pkg)

    with open(os.path.join(output_dir, 'packagesite_info.json'), "w") as f:
        json.dump(pkg_info, f, separators=(',', ':'))

def create_service(config_path, output_dir='.'):
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
        pkg_name = f'{dep["name"]}-{dep["version"]}.pkg'
        pkg_url = f'{dep["repo"]}/FreeBSD:{abi}:{arch}/{dep["path"]}/{pkg_name}'
        print(f'Loading {pkg_name} from: {pkg_url}')
        _download_pkg(pkg_url, os.path.join(output_dir, pkg_name))
        _gen_pkgsite_info_from_pkg(os.path.join(output_dir, pkg_name), output_dir)

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
    with urllib.request.urlopen(url, timeout=30) as req:
        with open(file, 'wb') as f:
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
        with tarfile.open(fileobj=decompressed_data, mode='r:') as tar:
            with open(os.path.join(output_dir, "packagesite_info.json"), "w") as f:
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

    parser_create_manifest = subparsers.add_parser('create-manifest', help='Create manifest files')
    parser_create_manifest.add_argument('config_path', help='Path to the config.yml file')
    parser_create_manifest.add_argument('--abi', required=True, help='ABI')
    parser_create_manifest.add_argument('--arch', required=True, help='Architecture')
    parser_create_manifest.add_argument('--output-dir', required=False, default='.', help='Directory to output the manifest files (default: current directory)')

    parser_create_packagesite_info = subparsers.add_parser('create-packagesite-info', help='Create package site info')
    parser_create_packagesite_info.add_argument('compact_manifest_path', help='Path to the +COMPACT_MANIFEST file')
    parser_create_packagesite_info.add_argument('--output-dir', required=False, default='.', help='Directory to output the packagesite info file (default: current directory)')

    parser_create_service = subparsers.add_parser('create-service', help='Create service file')
    parser_create_service.add_argument('config_path', help='Path to the config.yml file')
    parser_create_service.add_argument('--output-dir', required=False, default='.', help='Directory to output the service file (default: current directory)')

    parser_redistribute_pkg = subparsers.add_parser('redistribute-pkg', help='Redistribute package')
    parser_redistribute_pkg.add_argument('config_path', help='Path to the config.yml file')
    parser_redistribute_pkg.add_argument('--abi', required=True, help='ABI')
    parser_redistribute_pkg.add_argument('--arch', required=True, help='Architecture')
    parser_create_service.add_argument('--output-dir', required=False, default='.', help='Directory to output the package & packagesite info file  (default: current directory)')

    args = parser.parse_args()

    if args.command == 'create-manifest':
        create_manifest(args.config_path, args.abi, args.arch, args.output_dir)
    elif args.command == 'create-packagesite-info':
        create_packagesite_info(args.compact_manifest_path, args.output_dir)
    elif args.command == 'create-service':
        create_service(args.config_path, args.output_dir)
    elif args.command == 'redistribute-pkg':
        redistribute_pkg(args.config_path, args.abi, args.arch, args.output_dir)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
