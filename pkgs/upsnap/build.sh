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
git clone --branch "$VERSION" "$SRC_REPO" "${GH_WS}/src"
echo "::endgroup::"

echo "::group::Build frontend"
cd "${GH_WS}/src"
jq '.scripts.build = "svelte-kit sync && vite build"' frontend/package.json > tmp.json && mv tmp.json frontend/package.json
npm --prefix=./frontend install --silent
PUBLIC_VERSION=$VERSION npm --prefix=./frontend run build -- --logLevel error --clearScreen false | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"
cp -r ./frontend/build/* ./backend/pb_public/
echo "::endgroup::"

echo "::group::Build backend"
cd "${GH_WS}/src/backend"
go mod tidy
GOOS=freebsd GOARCH="${ARCH}" CGO_ENABLED=0 go build
echo "::endgroup::"

# Create Directories
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Copy Binary
cp "${GH_WS}/src/backend/upsnap" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"

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
