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

def folder_size(folder):
    total_size = 0
    for dirpath, _, filenames in os.walk(folder):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    return total_size

src_folder = os.environ.get('PKG_NAME')
workspace = os.environ.get('GITHUB_WORKSPACE')
abi = os.environ.get('ABI')
arch = os.environ.get('ARCH')

config_path = os.path.join(workspace, "repo", "pkg-src", src_folder, "config.yml")
with open(config_path, "r") as f:
    pkg_config = yaml.safe_load(f)
manifest = pkg_config["pkg_manifest"]
manifest['arch'] = f'FreeBSD:{abi}:{arch}'
manifest['flatsize'] = folder_size("pkg")

with open('+COMPACT_MANIFEST', "w") as f:
    json.dump(manifest, f, separators=(',', ':'))

manifest['files'] = {}
with chdir("pkg"):
    for root, _, files in os.walk('.'):
        if files:
            for file in files:
                file_path = os.path.join(root, file)
                manifest['files'][f'{os.sep}{os.path.relpath(file_path, ".")}'] = sha256sum(file_path)

with open('+MANIFEST', "w") as f:
    json.dump(manifest, f, separators=(',', ':'))
