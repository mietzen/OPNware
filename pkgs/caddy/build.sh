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
VERSION_SEP=$(pkg-tool dump "${CONFIG}" build_config.enhancement_version_separator)
FULL_VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
VERSION=${FULL_VERSION%%"$VERSION_SEP"*}
SRC_REPO=$(pkg-tool dump "${CONFIG}" build_config.src_repo)
CADDY_PLUGINS=(
    "github.com/caddy-dns/porkbun"
    "github.com/mholt/caddy-dynamicdns"
    "github.com/mietzen/caddy-dns-opnsense"
    "github.com/mietzen/libdns-opnsense-dnsmasq"
    "github.com/mietzen/libdns-opnsense-unbound"
    "github.com/lucaslorentz/caddy-docker-proxy/v2"
)

echo "::group::Install xCaddy"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
echo "::endgroup::"

echo "Cross Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/build"
chmod 0755 "${DIST_ROOT}/build"

echo "::group::Build Caddy Binary"
cd "${DIST_ROOT}/build"
GOOS=freebsd GOARCH="${ARCH}" xcaddy build "v${VERSION}" \
    $(printf -- "--with %s " "${CADDY_PLUGINS[@]}") \
    --output "${DIST_ROOT}/build/caddy"
echo "::endgroup::"
cd "${DIST_ROOT}"

# Create Directories for Packaging
mkdir -p "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"
mkdir -p "${DIST_ROOT}/dist/pkg/opt/opnware/bin"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}" "${DIST_ROOT}/dist/pkg/opt/opnware/bin"

# Copy Binary
cp "${DIST_ROOT}/build/caddy" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
chmod 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/${PKG_NAME}"
cd "${DIST_ROOT}/dist/pkg/opt/opnware/bin/"
ln -s "../pkgs/${PKG_NAME}/${PKG_NAME}" "${PKG_NAME}"
cd "${DIST_ROOT}"

# Copy License
curl -o "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/LICENSE" -L "${SRC_REPO}/raw/refs/tags/v${VERSION}/LICENSE"
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
cp "${REPO_ROOT}/pkgs/${PKG_NAME}/assets/.env.example" "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}/.env.example"
chmod -R 0755 "${DIST_ROOT}/dist/pkg/opt/opnware/pkgs/${PKG_NAME}"

# Create BSD distribution pkg
cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
