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

# Relocate rc.d script and docker-wrapper to target paths
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/etc/rc.d/docker" \
    "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/docker"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/opnware/docker"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/opnware/docker"
if [ -f "${SCRIPT_DIR}/src/usr/local/share/opnware/docker/os.img.zst" ]; then
    install -m 0644 "${SCRIPT_DIR}/src/usr/local/share/opnware/docker/os.img.zst" \
        "${DIST_ROOT}/dist/pkg/usr/local/share/opnware/docker/os.img.zst"
fi

# Clean double-nested usr/local staging
rm -rf "${DIST_ROOT}/dist/pkg/usr/local/usr/local"

# License file
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-docker"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-docker"
cp "${REPO_ROOT}/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-docker/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-docker/LICENSE"

# Normalize permissions
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/docker"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Docker/"*.php 2>/dev/null || true
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Docker/"*.py 2>/dev/null || true

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
