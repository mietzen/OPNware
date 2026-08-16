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
rm -rf "${DIST_ROOT}/src-${PKG_NAME}"
git clone --branch "v${VERSION}" --depth 1 "${SRC_REPO}" "${DIST_ROOT}/src-${PKG_NAME}"
echo "::endgroup::"

echo "::group::Build Binary"
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/bin"
cd "${DIST_ROOT}/src-${PKG_NAME}"
GOOS=freebsd GOARCH="${ARCH}" CGO_ENABLED=0 go build \
    -o "${DIST_ROOT}/dist/pkg/usr/local/bin/xcaddy" ./cmd/xcaddy
echo "::endgroup::"

# Create Directories (FreeBSD default paths)
BIN_DIR="${DIST_ROOT}/dist/pkg/usr/local/bin"
DOC_DIR="${DIST_ROOT}/dist/pkg/usr/local/share/doc/${PKG_NAME}"
mkdir -p "${BIN_DIR}" "${DOC_DIR}"
chmod 0755 "${BIN_DIR}" "${DOC_DIR}"

# Binary
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/bin/xcaddy"

# Copy License
cp "${DIST_ROOT}/src-${PKG_NAME}/LICENSE" "${DOC_DIR}/LICENSE"
chmod 0644 "${DOC_DIR}/LICENSE"

# Provide a link to the Source Code
cat <<EOF > "${DOC_DIR}/SOURCE"
This software is licensed under the Apache-2.0 license.
You may obtain a copy of the source code at:
$SRC_REPO/archive/refs/tags/v$VERSION.tar.gz
EOF
chmod 0644 "${DOC_DIR}/SOURCE"

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
