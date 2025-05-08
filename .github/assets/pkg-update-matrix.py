#!/usr/bin/env python3

import os
import sys
import yaml
import json
import re
import io
import requests
import tarfile
import zstandard
import logging
from pathlib import Path
from requests.compat import urljoin, urlparse, quote_plus

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s', stream=sys.stderr)

packagesite_cache = {}

def multi_urljoin(*parts):
    return urljoin(parts[0], "/".join(quote_plus(part.strip("/"), safe="/") for part in parts[1:]))

def detect_pkg_comp_fmt(url_base: str, abi_arch: str, path: str) -> str:
    """Detect the compression algorithm used by checking meta.conf"""
    url_abi_arch = abi_arch.replace('-', ':')
    meta_conf_url = multi_urljoin(url_base, url_abi_arch, path, "meta.conf")

    try:
        response = requests.get(meta_conf_url)
        if response.status_code == 200:
            format_match = re.search(r'packing_format\s*=\s*"?([^"]+)"?', response.text)
            if format_match:
                return format_match.group(1)
    except Exception as e:
        logging.error(f"Error detecting compression: {e}")
        sys.exit(1)

def extract_packagesite(pkgsite_data: bytes, compression_format: str) -> None:
    """Extract packagesite.yaml based on the compression format"""
    pkgsite = []
    try:
        if compression_format == "tzst":
            with io.BytesIO(pkgsite_data) as f:
                dctx = zstandard.ZstdDecompressor()
                with dctx.stream_reader(f) as decompressed_stream:
                    decompressed_data = io.BytesIO(decompressed_stream.read())
                    with tarfile.open(fileobj=decompressed_data, mode='r:') as tar:
                        content = tar.extractfile('packagesite.yaml').read()
        else:
            with tarfile.open(fileobj=io.BytesIO(pkgsite_data), mode=f'r:{compression_format[1:]}') as tar:
                content = tar.extractfile('packagesite.yaml').read()
    except Exception as e:
        logging.error(f"Failed to extract packagesite.yaml: {e}")
        sys.exit(1)

    for line in io.StringIO(content.decode()).readlines():
        pkgsite.append(json.loads(line))

    return pkgsite

def load_packagesite(url_base: str, abi_arch: str, path: str) -> dict:
    domain = urlparse(url_base).netloc.replace('.', '-')
    repo_key = f"{domain}-{abi_arch}-{path}"
    url_abi_arch = abi_arch.replace('-', ':')
    url = multi_urljoin(url_base, url_abi_arch, path, "packagesite.pkg")

    global packagesite_cache

    # Download and process packagesite if needed
    if not repo_key in packagesite_cache:
        logging.debug(f"Loading packagesite.pkg for: {domain}")

        response = requests.get(url)
        if response.status_code != 200:
            logging.error(f"Failed to download {url}, status code: {response.status_code}")
            sys.exit(1)

        compression_format = detect_pkg_comp_fmt(url_base, abi_arch, path)
        logging.debug(f"Detected compression format: {compression_format}")

        packagesite_data = extract_packagesite(response.content, compression_format)
        packagesite_cache[repo_key] = packagesite_data

    return packagesite_cache[repo_key]

def get_version_bsd_repo(pkg_name: str, config: dict, abi_arch: str) -> str:
    """Process a package with redistribute configuration"""
    url_base = config.get('redistribute', {}).get('repo', '')
    path = config.get('redistribute', {}).get('path', '').split('/')[0]

    packagesite_data = load_packagesite(url_base, abi_arch, path)

    remote_version = None
    for package in packagesite_data:
        if package.get('name') == pkg_name:
            remote_version = package.get('version')
            break

    if not remote_version:
        logging.error(f"{pkg_name} not found in packagesite.yaml from {url_base}")
        sys.exit(1)

    return remote_version

def get_version_gh_repo(pkg_name: str, config: dict) -> str:
    """Process a package with GitHub source repository"""
    repo_url = config.get('build_config', {}).get('src_repo', '')

    if 'github.com' not in repo_url:
        logging.error(f"No method implemented to check new release in {repo_url}")
        sys.exit(1)

    repo_match = re.search(r'https://github.com/([^/]+/[^/]+)', repo_url)
    if not repo_match:
        logging.error(f"Could not parse GitHub repository from URL: {repo_url}")
        sys.exit(1)

    gh_repo = repo_match.group(1)
    api_url = f"https://api.github.com/repos/{gh_repo}/releases/latest"
    headers = {}

    github_token = os.environ.get('GITHUB_TOKEN')
    if github_token:
        headers['Authorization'] = f"token {github_token}"

    response = requests.get(api_url, headers=headers)
    if response.status_code != 200:
        logging.error(f"Failed to get release info from GitHub API: {response.status_code}")
        sys.exit(1)

    release_data = response.json()
    remote_version = release_data.get('tag_name', '').lstrip('v')

    if not remote_version:
        logging.error(f"{pkg_name} no release found under: https://api.github.com/repos/{gh_repo}/releases")
        sys.exit(1)

    return remote_version

def get_version_sf_repo(pkg_name: str, config: dict) -> str:
    """Process a package with Sourceforge source repository"""
    repo_url = config.get('build_config', {}).get('src_repo', '')

    if 'sf.net' not in repo_url:
        logging.error(f"No method implemented to check new release in {repo_url}")
        sys.exit(1)

    repo_match = re.search(r'https://git.code.sf.net/p/([^/]+/code)', repo_url)
    if not repo_match:
        logging.error(f"Could not parse Sourceforge repository from URL: {repo_url}")
        sys.exit(1)

    sf_repo = repo_match.group(1).split('/')[0]
    api_url = f"https://sourceforge.net/projects/{sf_repo}/best_release.json"

    response = requests.get(api_url)
    if response.status_code != 200:
        logging.error(f"Failed to get release info from Sourceforge API: {response.status_code}")        
        logging.error(f"API URL: {api_url}")
        sys.exit(1)

    release_data = response.json()
    try:
        remote_version = release_data.get('release').get('filename').split('/')[2]
    except Exception:
        logging.error(f"{pkg_name} no release found under: https://sourceforge.net/projects/{sf_repo}")
        sys.exit(1)

    return remote_version

def main():
    for config_file in Path('./pkgs').glob('*/config.yml'):
        pkg_path = config_file.parent
        pkg_name = pkg_path.name
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

        if config.get('redistribute', False):
            local_version = {}
            remote_version = {}
            for abi_arch in config.get('redistribute', {}).get('version', {}).keys():
                local_version[abi_arch] = config['redistribute']['version'][abi_arch]
                remote_version[abi_arch] = get_version_bsd_repo(pkg_name, config, abi_arch)
        else:
            local_version = {'ALL': config.get('pkg_manifest', {}).get('version')}
            repo_url = config.get('build_config', {}).get('src_repo', '')
            if 'github.com' in repo_url:
                remote_version = {'ALL': get_version_gh_repo(pkg_name, config)}
            elif 'sf.net' in repo_url:
                remote_version = {'ALL': get_version_sf_repo(pkg_name, config)}
            else:
                logging.error(f"No method implemented to check new release in {repo_url}")
                sys.exit(1)

        if not local_version:
            logging.error(f"{pkg_name} no version found under: {pkg_path}/config.yml")
            sys.exit(1)

        matrix={'pkg': [],'include': []}

        for abi_arch in local_version:
            if str(remote_version[abi_arch]) != str(local_version[abi_arch]):
                matrix['pkg'].append(pkg_name)
                matrix['include'].append({'pkg': pkg_name, 'abi_arch': abi_arch, 'version': remote_version[abi_arch]})

        if matrix['pkg']:
            print(json.dumps(matrix))

if __name__ == '__main__':
    main()
