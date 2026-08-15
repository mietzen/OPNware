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
SRC_REPO=$(pkg-tool dump "${CONFIG}" build_config.src_repo)
# Homer is versioned independently of the os-homer plugin version (0.1.0),
# so the upstream release the dashboard is built from is pinned here.
HOMER_VERSION="26.4.2"

echo "::group::Install pnpm"
npm install -g pnpm@latest-10
echo "::endgroup::"

echo "Building ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

echo "::group::Git Checkout Repository"
rm -rf "${DIST_ROOT}/src"
git clone --depth 1 --branch "v${HOMER_VERSION}" "${SRC_REPO}" "${DIST_ROOT}/src"
echo "::endgroup::"

echo "::group::Building Homer"
cd "${DIST_ROOT}/src"
pnpm install
pnpm build
echo "::endgroup::"

# Create the payload staging root (FreeBSD default paths under dist/pkg).
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local"

# Stage the plugin source tree (MVC, configd actions/templates, rc script, ...).
cp -R "${SCRIPT_DIR}/src/." "${DIST_ROOT}/dist/pkg/usr/local/"

# The rc.d script is staged usr/local-prefixed in the plugin tree (everything
# else in src is /usr/local-relative); relocate it to the payload's
# usr/local/etc/rc.d and drop the double-prefixed copy.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/etc/rc.d/homer" \
    "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/homer"
rm -rf "${DIST_ROOT}/dist/pkg/usr/local/usr/local"

# Stage the built static dashboard under /usr/local/www/homer.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/www"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/www"
cp -R "${DIST_ROOT}/src/dist/." "${DIST_ROOT}/dist/pkg/usr/local/www/homer/"

# Stage the license and source pointer under /usr/local/share/doc/homer.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer"
cp "${DIST_ROOT}/src/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer/LICENSE"

# Provide Source Code Link
cat <<EOF > "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer/SOURCE"
This software is licensed under the Apache License, Version 2.0.
You may obtain a copy of the source code at:
${SRC_REPO}/archive/refs/tags/v${HOMER_VERSION}.tar.gz
EOF
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/homer/SOURCE"

# Normalize permissions (the rc.d script must stay executable).
find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/homer"

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
