#!/usr/bin/env python3

import os
import sys
import yaml
import json
import re
import requests
import tarfile
import zstandard
from pathlib import Path
from requests.compat import urljoin

def detect_compression(url_base: str, abi_arch: str, path: str) -> str:
    """Detect the compression algorithm used by checking meta.conf"""
    url_abi_arch = abi_arch.replace('-', ':')
    meta_conf_url = urljoin(url_base, url_abi_arch, path, "meta.conf")

    try:
        response = requests.get(meta_conf_url)
        if response.status_code == 200:
            format_match = re.search(r'packing_format\s*=\s*"?([^"]+)"?', response.text)
            if format_match:
                return format_match.group(1)
    except Exception as e:
        print(f"Error detecting compression: {e}")
        sys.exit(1)

def extract_packagesite(pkg_file: str, output_file: str, compression_format: str) -> None:
    """Extract packagesite.yaml based on the compression format"""
    try:
        if compression_format == "tzst":
            # Handle zstd compression
            with open(pkg_file, 'rb') as f:
                dctx = zstandard.ZstdDecompressor()
                with dctx.stream_reader(f) as reader:
                    with tarfile.open(fileobj=reader, mode='r|') as tar:
                        content = tar.extractfile('packagesite.yaml').read()
                        with open(output_file, 'wb') as out_file:
                            out_file.write(content)
        else:
            with tarfile.open(pkg_file, f'r:{compression_format[1:]}') as tar:
                content = tar.extractfile('packagesite.yaml').read()
                with open(output_file, 'wb') as out_file:
                    out_file.write(content)
    except Exception as e:
        print(f"Failed to extract packagesite.yaml: {e}")
        sys.exit(1)

def format_packagesite_yaml(yaml_file: str) -> None:
    """Format the packagesite.yaml file as a proper yaml array"""
    data = []
    with open(yaml_file, 'r') as f:
        lines = f.readlines()
        for line in lines:
            data.append(json.loads(line))
    with open(yaml_file, 'w') as f:
        yaml.dump(data, f)

def load_packagesite_data(url_base: str, abi_arch: str, path: str) -> dict:
    packagesite_yaml = f"{abi_arch}-{path}-packagesite.yaml"
    packagesite_pkg = f"{abi_arch}-{path}-packagesite.pkg"
    url_abi_arch = abi_arch.replace('-', ':')
    url = urljoin(url_base, url_abi_arch, path, "packagesite.pkg")

    # Download and process packagesite if needed
    if not os.path.exists(packagesite_yaml):
        print(f"Loading packagesite.pkg from: {url}")

        # Download packagesite.pkg
        response = requests.get(url)
        if response.status_code != 200:
            print(f"Failed to download {url}, status code: {response.status_code}")
            sys.exit(1)

        with open(packagesite_pkg, 'wb') as f:
            f.write(response.content)

        # Determine compression format
        compression_format = detect_compression(url_base, abi_arch, path)
        print(f"Detected compression format: {compression_format}")

        # Extract the packagesite.yaml
        extract_packagesite(packagesite_pkg, packagesite_yaml, compression_format)

        # Format the packagesite.yaml file
        format_packagesite_yaml(packagesite_yaml)

    # Load packagesite data
    with open(packagesite_yaml, 'r') as f:
        packagesite_data = yaml.safe_load(f)

    return packagesite_data

def process_redist_pkg(
    pkg_path: Path,
    pkg_name: str,
    config: dict,
) -> None:
    """Process a package with redistribute configuration"""
    for abi_arch in config.get('redistribute', {}).get('version', {}).keys():
        url_base = config.get('redistribute', {}).get('repo', '')
        path = config.get('redistribute', {}).get('path', '').split('/')[0]

        packagesite_data = load_packagesite_data(abi_arch, path, url_base)

        # Find package in packagesite data
        remote_version = None
        for package in packagesite_data:
            if package.get('name') == pkg_name:
                remote_version = package.get('version')
                break

        if not remote_version:
            print(f"{pkg_name} not found in packagesite.yaml from {url_base}")
            sys.exit(1)

        # Get local version
        local_version = config.get('redistribute', {}).get('version', {}).get(abi_arch)

        if not local_version:
            print(f"{pkg_name} no version found under: {pkg_path}/config.yml")
            sys.exit(1)

        # Compare versions
        if remote_version != local_version:
            msg = f"{pkg_name}, upgrading from: {local_version} to: {remote_version}"
            print(msg)

            # Update the config file
            config['redistribute']['version'][abi_arch] = remote_version
            with open(pkg_path / 'config.yml', 'w') as f:
                yaml.dump(config, f, sort_keys=False)


def process_github_pkg(
    pkg_path: Path,
    pkg_name: str,
    config: dict,
) -> None:
    """Process a package with GitHub source repository"""
    repo_url = config.get('build_config', {}).get('src_repo', '')

    # Check if it's a GitHub repository
    if 'github.com' not in repo_url:
        print(f"No method implemented to check new release in {repo_url}")
        sys.exit(1)

    local_version = config.get('pkg_manifest', {}).get('version')

    if not local_version:
        print(f"{pkg_name} no version found under: {pkg_path}/config.yml")
        sys.exit(1)

    # Extract repo owner and name
    repo_match = re.search(r'https://github.com/([^/]+/[^/]+)', repo_url)
    if not repo_match:
        print(f"Could not parse GitHub repository from URL: {repo_url}")
        sys.exit(1)

    repo = repo_match.group(1)

    # Get the latest release version using GitHub API directly
    api_url = f"https://api.github.com/repos/{repo}/releases/latest"
    headers = {}

    # Use GitHub token if available
    github_token = os.environ.get('GITHUB_TOKEN')
    if github_token:
        headers['Authorization'] = f"token {github_token}"

    response = requests.get(api_url, headers=headers)
    if response.status_code != 200:
        print(f"Failed to get release info from GitHub API: {response.status_code}")
        sys.exit(1)

    release_data = response.json()
    remote_version = release_data.get('tag_name', '').lstrip('v')

    if not remote_version:
        print(f"{pkg_name} no release found under: https://api.github.com/repos/{repo}/releases")
        sys.exit(1)

    # Compare versions
    if remote_version != local_version:
        msg = f"{pkg_name}, upgrading from: {local_version} to: {remote_version}"
        print(msg)

        # Update the config file
        config['pkg_manifest']['version'] = remote_version
        with open(pkg_path / 'config.yml', 'w') as f:
            yaml.dump(config, f, sort_keys=False)

def main():
    # Process each package directory
    for config_file in Path('./pkgs').glob('*/config.yml'):
        pkg_path = config_file.parent
        pkg_name = pkg_path.name
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

        # Check if package has redistribute config
        has_redistribute = config.get('redistribute', False)
        if has_redistribute and (has_redistribute is True or isinstance(has_redistribute, dict)):
            process_redist_pkg(pkg_path, pkg_name, config)
        else:
            process_github_pkg(pkg_path, pkg_name, config)

if __name__ == '__main__':
    main()