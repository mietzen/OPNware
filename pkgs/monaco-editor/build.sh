#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"

echo "Building monaco-editor - ARCH: ${ARCH} - ABI: ${ABI}"

VENDOR_DIR="${SCRIPT_DIR}/assets/vendor"
PKG_VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)

# The package version must track the vendored monaco-editor release; a
# refreshed vendor without a version bump fails here instead of shipping a
# silently mismatched package. A FreeBSD revision suffix (_1) is allowed for
# package-only changes (e.g. an added bootstrap worker) — the base version
# still must equal the vendored monaco release.
MONACO_VERSION=$(python3 -c "import json;print(json.load(open('${VENDOR_DIR}/monaco/package.json'))['version'])")
PKG_BASE=$(printf '%s' "${PKG_VERSION}" | sed -E 's/_[0-9]+$//')
if [ "${MONACO_VERSION}" != "${PKG_BASE}" ]; then
    echo "ERROR: vendored monaco-editor is ${MONACO_VERSION} but config.yml says ${PKG_VERSION} — bump pkg_manifest.version"
    exit 1
fi

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js"

cp -R "${VENDOR_DIR}/." "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor/"
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
