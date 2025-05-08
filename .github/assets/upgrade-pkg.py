#!/usr/bin/env python3

import sys
import yaml
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s', stream=sys.stderr)

def main():
    pkg_name = sys.argv[1]
    remote_version = sys.argv[2]
    abi_arch = sys.argv[3]
    config_file = f'./pkgs/{pkg_name}/config.yml'
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)

    if config.get('redistribute', False):
        local_version[abi_arch] = config['redistribute']['version'][abi_arch]
    else:
        local_version = {'ALL': config.get('pkg_manifest', {}).get('version')}

    if not local_version:
        logging.error(f"{pkg_name} no version found under: {config_file}")
        sys.exit(1)

    if config.get('redistribute', False):
        config['redistribute']['version'][abi_arch] = remote_version
    else:
        config['pkg_manifest']['version'] = remote_version

    with Path(config_file) as file:
        file.write_text(
            file.read_text().replace(
                str(local_version[abi_arch]),
                str(remote_version)))

if __name__ == '__main__':
    main()
