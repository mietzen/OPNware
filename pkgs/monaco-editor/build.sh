#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"
WORK="${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor"

# monaco-editor's version comes from config.yml; bumps are manual (build.sh
# fetches the pinned release at build time).

echo "Building monaco-editor - ARCH: ${ARCH} - ABI: ${ABI}"

PKG_NAME=$(pkg-tool dump "${CONFIG}" pkg_manifest.name)
PKG_VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
# pkg_manifest.version is the source of truth for the monaco-editor release
# to fetch; the base version (with any FreeBSD _N revision suffix stripped)
# is the npm version.
MONACO_VERSION=$(printf '%s' "${PKG_VERSION}" | sed -E 's/_[0-9]+$//')

mkdir -p "${WORK}"
chmod 0755 "${WORK}"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

# 1. monaco-editor (drives the package version).
npm pack "monaco-editor@${MONACO_VERSION}" --silent --pack-destination "${TMP}" >/dev/null
mkdir -p "${TMP}/monaco"
tar -xzf "${TMP}/monaco-editor-${MONACO_VERSION}.tgz" -C "${TMP}/monaco"
rm -rf "${WORK}/monaco"
mkdir -p "${WORK}/monaco"
cp -R "${TMP}/monaco/package/min/vs" "${WORK}/monaco/vs"
cp "${TMP}/monaco/package/package.json" "${WORK}/monaco/package.json"

# 2. Hand-written Caddyfile Monarch grammar (checked in, not fetched). The
#    editor pages load it through Monaco's AMD loader as the 'caddyfile'
#    module (/ui/js/vendor/caddyfile.js).
cp "${SCRIPT_DIR}/src/caddyfile.js" "${WORK}/caddyfile.js"

# 3. License (monaco is MIT). Staged as a generic doc LICENSE so pkg-tool's
#    _stage_licenses copies it to
#    /usr/local/share/licenses/monaco-editor-<ver>/MIT (Firmware -> Packages).
DOC_DIR="${DIST_ROOT}/dist/pkg/usr/local/share/doc/${PKG_NAME}"
mkdir -p "${DOC_DIR}"
cp "${TMP}/monaco/package/LICENSE" "${DOC_DIR}/LICENSE"
chmod 0644 "${DOC_DIR}/LICENSE"

find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
