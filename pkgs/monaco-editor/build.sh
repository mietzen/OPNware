#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"
WORK="${DIST_ROOT}/dist/pkg/usr/local/opnsense/www/js/vendor"

# The TextMate stack is refreshed alongside monaco-editor. Its versions are
# pinned here (they move rarely); monaco-editor's version comes from
# config.yml so the daily update flow can drive refresh PRs for it.
TEXTMATE_VERSION="9.3.2"
ONIGURUMA_VERSION="2.0.1"

echo "Building monaco-editor - ARCH: ${ARCH} - ABI: ${ABI}"

PKG_VERSION=$(pkg-tool dump "${CONFIG}" pkg_manifest.version)
# The package version is the source of truth for the monaco-editor release to
# fetch: the version guard below already requires the base version to equal
# the configured pin, so fetching at PKG_BASE keeps build and spec in lockstep.
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

# 2. TextMate stack (vscode-textmate + vscode-oniguruma).
npm pack "vscode-textmate@${TEXTMATE_VERSION}" --silent --pack-destination "${TMP}" >/dev/null
mkdir -p "${TMP}/textmate"
tar -xzf "${TMP}/vscode-textmate-${TEXTMATE_VERSION}.tgz" -C "${TMP}/textmate"
mkdir -p "${WORK}/textmate/vscode-textmate"
cp "${TMP}/textmate/package/release/main.js" "${WORK}/textmate/vscode-textmate/main.js"
cp "${TMP}/textmate/package/package.json" "${WORK}/textmate/vscode-textmate/package.json"

npm pack "vscode-oniguruma@${ONIGURUMA_VERSION}" --silent --pack-destination "${TMP}" >/dev/null
mkdir -p "${TMP}/oniguruma"
tar -xzf "${TMP}/vscode-oniguruma-${ONIGURUMA_VERSION}.tgz" -C "${TMP}/oniguruma"
mkdir -p "${WORK}/textmate/vscode-oniguruma/release"
cp "${TMP}/oniguruma/package/release/main.js" "${WORK}/textmate/vscode-oniguruma/release/main.js"
cp "${TMP}/oniguruma/package/release/onig.wasm" "${WORK}/textmate/vscode-oniguruma/release/onig.wasm"

# 3. Hand-written OPNware artifacts (checked in, not fetched).
cp "${SCRIPT_DIR}/src/editor.worker.bootstrap.js" "${WORK}/monaco/vs/editor/editor.worker.bootstrap.js"
cp "${SCRIPT_DIR}/src/monaco-editor-textmate.js" "${WORK}/textmate/monaco-editor-textmate.js"
cp "${SCRIPT_DIR}/src/caddyfile.tmLanguage.json" "${WORK}/caddyfile.tmLanguage.json"

# 4. Apply the CSP worker patch to the pristine monaco tree. The patch is
#    MADE here (never copied), so a version bump can't silently lose it: the
#    codemod fails the build if the expected pristine patterns are absent.
python3 "${SCRIPT_DIR}/src/patch-csp-worker.py" "${WORK}"

# 5. License files (monaco is MIT; the textmate stack ships its own).
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/licenses/monaco-editor-${PKG_VERSION}"
cp "${TMP}/monaco/package/LICENSE" \
    "${DIST_ROOT}/dist/pkg/usr/local/share/licenses/monaco-editor-${PKG_VERSION}/LICENSE"
find "${DIST_ROOT}/dist/pkg/usr/local/share/licenses" -type f -exec chmod 0644 {} +

find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
