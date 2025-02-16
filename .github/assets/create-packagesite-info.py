import os
import json
import hashlib

def sha256sum(filename):
    with open(filename, 'rb', buffering=0) as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

with open('pkg/+COMPACT_MANIFEST', "r") as f:
    pkg_info = json.load(f)

pkg = f'{pkg_info['name']}-{pkg_info['version']}.pkg'

pkg_info['path'] = f'All/{pkg}'
pkg_info['repopath'] = f'All/{pkg}'
pkg_info['sum'] = f'{sha256sum(pkg)}'
pkg_info['pkgsize'] = os.path.getsize(pkg)

with open('packagesite_info.json', "w") as f:
    json.dump(pkg_info, f, separators=(',', ':'))
