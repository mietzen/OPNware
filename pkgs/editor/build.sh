#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"

echo "Building editor - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js"

# Source of truth: the vendored tree lives in the os-caddy plugin source.
cp -R "${REPO_ROOT}/pkgs/os-caddy/assets/vendor/." "${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor/"
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
