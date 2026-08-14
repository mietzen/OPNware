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
VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
SRC_REPO=$(pkg-tool dump "${CONFIG}" build_config.src_repo)

echo "Cross Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/dist"
chmod 0755 "${DIST_ROOT}/dist"

echo "::group::Git checkout repository"
git clone --branch "$VERSION" "$SRC_REPO" "${DIST_ROOT}/src"
echo "::endgroup::"

echo "::group::Build frontend"
cd "${DIST_ROOT}/src"
jq '.scripts.build = "svelte-kit sync && vite build"' frontend/package.json > tmp.json && mv tmp.json frontend/package.json
npm --prefix=./frontend install --silent
PUBLIC_VERSION=$VERSION npm --prefix=./frontend run build -- --logLevel error --clearScreen false | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"
cp -r ./frontend/build/* ./backend/pb_public/
echo "::endgroup::"

echo "::group::Build backend"
cd "${DIST_ROOT}/src/backend"
go mod tidy
GOOS=freebsd GOARCH="${ARCH}" CGO_ENABLED=0 go build
echo "::endgroup::"

# Create Directories
mkdir -p "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Copy Binary
cp "${DIST_ROOT}/src/backend/upsnap" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"

# Copy License
cp "${DIST_ROOT}/src/LICENSE" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"

# Provide a link to the Source Code
cat <<EOF > "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"
This software is licensed under the MIT license.
You may obtain a copy of the source code at:
$SRC_REPO/archive/refs/tags/v$VERSION.tar.gz
EOF
chmod 0644 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
