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

# Our own MIT license for the plugin code.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy"
cp "${SCRIPT_DIR}/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy/LICENSE"

# The vendored Monaco/TextMate tree ships in the shared `editor` package
# (both plugins depend on it) — it is NOT copied into plugin payloads, so
# pkg never sees duplicate file ownership. See docs/design/shared-editor-vendor.md.

find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
# The periodic self-healing hook is a shell script and must stay executable.
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/periodic/daily/500.os-caddy-modules"

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
