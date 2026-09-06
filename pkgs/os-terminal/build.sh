#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
PKG_NAME=$(pkg-tool dump "${CONFIG}" pkg_manifest.name)
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"

echo "Building os-${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

# Create the payload staging root (FreeBSD default paths under dist/pkg).
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local"

# Stage the plugin source tree (MVC, configd actions/templates, rc script, ...).
cp -R "${SCRIPT_DIR}/src/." "${DIST_ROOT}/dist/pkg/usr/local/"
find "${DIST_ROOT}/dist/pkg/usr/local" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# Relocate double-prefixed rc.d script
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/etc/rc.d/terminal-service" \
    "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/terminal-service"
rm -rf "${DIST_ROOT}/dist/pkg/usr/local/usr/local"

# License file
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-terminal"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-terminal"
cp "${REPO_ROOT}/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-terminal/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-terminal/LICENSE"

# Normalize permissions
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/terminal-service"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Terminal/"*.php 2>/dev/null || true
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Terminal/"*.py 2>/dev/null || true

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
