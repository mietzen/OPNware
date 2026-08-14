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

echo "Cross Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"

echo "::group::Git checkout repository"
git clone --branch "v${VERSION}" "${SRC_REPO}" "${GH_WS}/src"
echo "::endgroup::"

echo "::group::Build Binary"
cd "${GH_WS}/src"
go mod tidy
GOOS=freebsd GOARCH="${ARCH}" go build
echo "::endgroup::"
cd "${GH_WS}"

# Create Directories
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/bin"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}" "${GH_WS}/dist/pkg/opt/opnware/bin"

# Copy Binary
cp "${GH_WS}/src/${PKG_NAME}" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
cd "${GH_WS}/dist/pkg/opt/opnware/bin/"
ln -s "../pkgs/${PKG_NAME}/${PKG_NAME}" "${PKG_NAME}"
cd "${GH_WS}"

# Copy License
cp "${GH_WS}/src/LICENSE" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"

# Provide a link to the Source Code
cat <<EOF > "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"
This software is licensed under the MIT license.
You may obtain a copy of the source code at:
$SRC_REPO/archive/refs/tags/v$VERSION.tar.gz
EOF
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"

# Create BSD distribution pkg
cd "${GH_WS}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
