#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"

echo "Building os-caddy - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local"
cp -R "${SCRIPT_DIR}/src/." "${DIST_ROOT}/dist/pkg/usr/local/"

# Shared vendored editor assets -> /opnsense/www/js/vendor (served as /ui/js/vendor).
# Shared repo-level asset; other plugins copy the same tree. See docs/design/shared-editor-vendor.md.
if [ -d "${SCRIPT_DIR}/assets/vendor" ]; then
    mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor"
    cp -R "${SCRIPT_DIR}/assets/vendor/." "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor/"
fi

find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
