#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${ARCH}"
ABI="${ABI}"
GH_WS="${GITHUB_WORKSPACE}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_DIR=$(echo "${SCRIPT_DIR#${GH_WS%/}/}" | cut -d'/' -f1)
PKG_NAME=$(yq -r '.[].name | select( . != null )' ${CONFIG})
VERSION=$(yq '.pkg_manifest.version' "${CONFIG}")
SRC_REPO=$(yq '.build_config.src_repo' "${CONFIG}")

echo "::group::Install pkg-tool"
pip install "file://${REPO_DIR}/pkg-tool"
echo "::endgroup::"

echo "Cross Compiling ${PKG_NAME} - ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"

echo "::group::Git Checkout Repository"
git clone --branch "v${VERSION}" "${REPO}" "${GH_WS}/src"
echo "::endgroup::"

echo "::group::Build Binary"
cd "${GH_WS}/src"
go mod tidy
GOOS=freebsd GOARCH="${ARCH}" go build
echo "::endgroup::"

# Create Directories for Packaging
mkdir -p "${GH_WS}/dist/pkg/opt/${PKG_NAME}"
mkdir -p "${GH_WS}/dist/pkg/etc/rc.d"
chmod 0755 "${GH_WS}/dist/pkg/opt/${PKG_NAME}" "${GH_WS}/dist/pkg/etc/rc.d"

# Copy Binary
cp "${GH_WS}/src/${PKG_NAME}" "${GH_WS}/dist/pkg/opt/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/${PKG_NAME}"

# Copy License
cp "${GH_WS}/src/LICENSE" "${GH_WS}/dist/pkg/opt/${PKG_NAME}/LICENSE"
chmod 0644 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/LICENSE"

# Provide Source Code Link
cat <<EOF > "${GH_WS}/dist/pkg/opt/${PKG_NAME}/SOURCE"
This software is licensed under the Apache License, Version 2.0.
You may obtain a copy of the source code at:
${REPO}/archive/refs/tags/v${VERSION}.tar.gz
EOF
chmod 0644 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/SOURCE"

# Copy Assets
cp -r "${GH_WS}/repo/pkgs/${PKG_NAME}/assets/" "${GH_WS}/dist/pkg/opt/${PKG_NAME}/"
chmod -R 0755 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/assets/"

# Create BSD distribution pkg
cd "${GH_WS}/dist"

# Create Service
pkg-tool create-service "${CONFIG}" --output-dir "./pkg/etc/rc.d/"

# Create Manifest
pkg-tool create-manifest "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"

# Create Package
tar -cf "${PKG_NAME}-${VERSION}.pkg" \
    --zstd \
    --owner=0 \
    --group=0 \
    --transform 's|^pkg||' \
    +COMPACT_MANIFEST +MANIFEST $(find pkg -type f)

# Create Packagesite Info
pkg-tool create-packagesite-info ./+COMPACT_MANIFEST

# Cleanup
rm -rf "${GH_WS}/dist/+MANIFEST" "${GH_WS}/dist/+COMPACT_MANIFEST" "${GH_WS}/dist/pkg"
