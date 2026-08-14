#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${1}"
ABI="${2}"
GH_WS="${GITHUB_WORKSPACE}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
PKG_NAME=$(pkg-tool dump "${CONFIG}" pkg_manifest.name)
VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
SRC_REPO=$(pkg-tool dump "${CONFIG}" build_config.src_repo)

echo "::group::Install pnpm"
npm install -g pnpm@latest-10
echo "::endgroup::"

echo "Building ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"

echo "::group::Git Checkout Repository"
git clone --branch "v${VERSION}" "${SRC_REPO}" "${GH_WS}/src"
echo "::endgroup::"

echo "::group::Generating Files"
cd "${GH_WS}/src"
pnpm install
pnpm build
echo "::endgroup::"

# Create Directories for Packaging
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d"

# Copying files
cp -r "${GH_WS}/src/dist" "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}"

# Copy License
cp "${GH_WS}/src/LICENSE" "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/LICENSE"
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/LICENSE"

# Provide Source Code Link
cat <<EOF > "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/SOURCE"
This software is licensed under the Apache License, Version 2.0.
You may obtain a copy of the source code at:
${SRC_REPO}/archive/refs/tags/v${VERSION}.tar.gz
EOF
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/SOURCE"

# Copy Assets
cp "${GH_WS}/repo/pkgs/${PKG_NAME}/assets/config.yml" "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/assets/config.yml"
cp "${GH_WS}/repo/pkgs/${PKG_NAME}/assets/homer.caddy" "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/homer.caddy"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/${PKG_NAME}/assets/config.yml"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/caddy/conf.d/homer.caddy"

# Create BSD distribution pkg
cd "${GH_WS}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
