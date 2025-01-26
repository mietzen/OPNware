import os
import json
import yaml
import hashlib

def chdir(folder):
    curdir= os.getcwd()
    os.chdir(folder)
    try: yield
    finally: os.chdir(curdir)

def sha256sum(filename):
    with open(filename, 'rb', buffering=0) as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

src_folder = os.environ('PKG_NAME')
workspace = os.environ('GITHUB_WORKSPACE')
abi = os.environ('ABI')
arch = os.environ('ARCH')

config_path = os.path.join(workspace, "repo", "pkg-src", src_folder, "config.yml")
with open(config_path, "r") as f:
    pkg_config = yaml.safe_load(f)
manifest = pkg_config["pkg_manifest"]
manifest['arch'] = f'FreeBSD:{abi}:{arch}'
manifest['flatsize'] = os.path.getsize(f"{manifest['name']}-{manifest['version']}.pkg")

with open('+COMPACT_MANIFEST', "r") as f:
    json.dump(manifest, f, separators=(',', ':'))

manifest['files'] = {}
with chdir("pkg"):
    for root, _, files in os.walk('.'):
        if files:
            for file in files:
                file_path = os.path.join(root, file)
                manifest['files'][f'{os.sep}{os.path.relpath(file_path, ".")}'] = sha256sum(file_path)

with open('+MANIFEST', "r") as f:
    json.dump(manifest, f, separators=(',', ':'))
