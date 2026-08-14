#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"
CONFIG="${SCRIPT_DIR}/config.yml"
PKG_NAME=$(pkg-tool dump "${CONFIG}" pkg_manifest.name)
VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
SRC_REPO=$(pkg-tool dump "${CONFIG}" build_config.src_repo)

echo "Cross Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/dist"
chmod 0755 "${DIST_ROOT}/dist"

echo "::group::Git Checkout Repository"
git clone --branch "v${VERSION}" "${SRC_REPO}" "${DIST_ROOT}/src"
echo "::endgroup::"

echo "::group::Build Binary"
cd "${DIST_ROOT}/src"
go mod tidy
GOOS=freebsd GOARCH="${ARCH}" go build
echo "::endgroup::"

# Create Directories for Packaging
mkdir -p "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Copy Binary
cp "${DIST_ROOT}/src/${PKG_NAME}" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"

# Copy License
cp "${DIST_ROOT}/src/LICENSE" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"

# Provide Source Code Link
cat <<EOF > "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"
This software is licensed under the Apache License, Version 2.0.
You may obtain a copy of the source code at:
${SRC_REPO}/archive/refs/tags/v${VERSION}.tar.gz
EOF
chmod 0644 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"

# Copy Assets
cp -Tr "${REPO_ROOT}/pkgs/${PKG_NAME}/assets" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
chmod -R 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
