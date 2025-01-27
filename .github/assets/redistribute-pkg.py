import os
import urllib.request
import yaml
import tarfile

src_folder = os.environ.get('PKG_NAME')
workspace = os.environ.get('GITHUB_WORKSPACE')
abi = os.environ.get('ABI')
arch = os.environ.get('ARCH')

def download_pkg(url, file):
    with urllib.request.urlopen(url, timeout=30) as req:
        with open(file,'wb') as f:
            f.write(req.read())

def create_pkgsite_info(pkg_name):
    with tarfile.open(pkg_name, 'r:') as tar:
        with open ("packagesite_info.json", "wb") as f:
            f.write(tar.extractfile('+COMPACT_MANIFEST').read())

config_path = os.path.join(workspace, "repo", "pkg-src", src_folder, "config.yml")
with open(config_path, "r") as f:
    pkg_config = yaml.safe_load(f)

if pkg_config['redistribute']:
    dep = pkg_config['redistribute']
    pkg_name = f'{dep['name']}-{dep['version']}.pkg'
    pkg_url = f'{dep['repo']}/FreeBSD:{abi}:{arch}/latest/ALL/{pkg_name}'
    download_pkg(pkg_url, pkg_name)
    create_pkgsite_info(pkg_name)
