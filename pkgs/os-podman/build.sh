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

# The rc.d script and podman-wrapper are staged usr/local-prefixed in the plugin tree (everything
# else in src is /usr/local-relative); relocate them to the payload's
# usr/local/etc/rc.d and usr/local/bin and drop the double-prefixed copy.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/etc/rc.d/podman-service" \
    "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/podman-service"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/bin"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/bin"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/bin/podman-wrapper" \
    "${DIST_ROOT}/dist/pkg/usr/local/bin/podman-wrapper"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/opnware"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/opnware"
install -m 0644 "${SCRIPT_DIR}/src/usr/local/share/opnware/apt-freebsd.conf" \
    "${DIST_ROOT}/dist/pkg/usr/local/share/opnware/apt-freebsd.conf"

rm -rf "${DIST_ROOT}/dist/pkg/usr/local/usr/local"

# License file
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-podman"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-podman"
cp "${REPO_ROOT}/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-podman/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-podman/LICENSE"

# Normalize permissions
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/podman-service"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/bin/podman-wrapper"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Podman/"*.php 2>/dev/null || true
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/Podman/"*.py 2>/dev/null || true

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
