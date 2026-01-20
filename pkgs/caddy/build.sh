#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${1}"
ABI="${2}"
GH_WS="${GITHUB_WORKSPACE}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_DIR=$(echo "${SCRIPT_DIR#${GH_WS%/}/}" | cut -d'/' -f1)
PKG_NAME=$(yq -r '.[].name | select( . != null )' ${CONFIG})
VERSION=$(yq '.pkg_manifest.version' "${CONFIG}")
SRC_REPO=$(yq '.build_config.src_repo' "${CONFIG}")
CADDY_PLUGINS=(
    "github.com/caddy-dns/porkbun"
    "github.com/mholt/caddy-dynamicdns"
    "github.com/mholt/caddy-events-exec"
    "github.com/mietzen/caddy-dynamicdns-cmd-source"
    "github.com/lucaslorentz/caddy-docker-proxy/v2"
)

echo "::group::Install pkg-tool"
pip install "file://${GH_WS}/${REPO_DIR}/pkg-tool"
echo "::endgroup::"

echo "::group::Install xCaddy"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
echo "::endgroup::"

echo "Cross Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/build"
chmod 0755 "${GH_WS}/build"

echo "::group::Build Caddy Binary"
cd "${GH_WS}/build"
GOOS=freebsd GOARCH="${ARCH}" xcaddy build "v${VERSION}" \
    $(printf -- "--with %s " "${CADDY_PLUGINS[@]}") \
    --output "${GH_WS}/build/caddy"
echo "::endgroup::"
cd "${GH_WS}"

# Create Directories for Packaging
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}" "${GH_WS}/dist/pkg/etc/rc.d" "${GH_WS}/dist/pkg/opt/opnware/bin"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}" "${GH_WS}/dist/pkg/etc/rc.d" "${GH_WS}/dist/pkg/opt/opnware/bin"

mkdir -p "${GH_WS}/dist/pkg/etc/rc.d"
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/bin"
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
mkdir -p "${GH_WS}/dist/pkg/opt/opnware/services/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/etc/rc.d"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/bin"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/services/${PKG_NAME}"

# Copy Binary
cp "${GH_WS}/build/caddy" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
cd "${GH_WS}/dist/pkg/opt/opnware/bin/"
ln -s "../pkgs/${PKG_NAME}/${PKG_NAME}" "${PKG_NAME}"
cd "${GH_WS}"

# Copy License
curl -o "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE" -L "${SRC_REPO}/raw/refs/tags/v${VERSION}/LICENSE"
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE"

# Provide Source Code Link
cat <<EOF > "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"
This software is licensed under the Apache License, Version 2.0.
You may obtain a copy of the source code at:
${SRC_REPO}/archive/refs/tags/v${VERSION}.tar.gz
EOF
chmod 0644 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/SOURCE"

# Copy Assets
cp -Tr "${GH_WS}/repo/pkgs/${PKG_NAME}/assets" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
cp "${GH_WS}/repo/pkgs/${PKG_NAME}/assets/.env" "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/.env"
chmod -R 0755 "${GH_WS}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Create BSD distribution pkg
cd "${GH_WS}/dist"

# Create Service
pkg-tool create-service "${CONFIG}" --output-dir "./pkg/opt/opnware/services/${PKG_NAME}"
cd ./pkg/etc/rc.d/
ln -s "../../opt/opnware/services/${PKG_NAME}/${PKG_NAME}" "./${PKG_NAME}"
cd "${GH_WS}/dist"

# Create Manifest
pkg-tool create-manifest "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"

# Create Package
tar -cf "${PKG_NAME}-${VERSION}.pkg" \
    --zstd \
    --owner=0 \
    --group=0 \
    --transform 's|^pkg||' \
    +COMPACT_MANIFEST +MANIFEST $(find pkg -type f) $(find pkg -type l)

# Create Packagesite Info
pkg-tool create-packagesite-info ./+COMPACT_MANIFEST

# Cleanup
rm -rf "${GH_WS}/dist/+MANIFEST" "${GH_WS}/dist/+COMPACT_MANIFEST" "${GH_WS}/dist/pkg"
