#!/bin/bash
set -euo pipefail

# OPNware — one-command refresh of the shared vendored editor.
#
# The monaco-editor package (pkgs/monaco-editor) ships a checked-in vendor tree
# (monaco-editor + the TextMate stack). The daily check-updates flow detects a
# new npm release and routes it here (update.yml, abi_arch 'vendor'); this
# script re-vendors AND bumps, then opens a PR that is NOT auto-merged — the
# human reviews the resulting diff, that review IS the safety gate. Can also
# be run by hand as the manual refresh.
#
# What it does:
#   1. npm-pack the latest monaco-editor, replace vendor/monaco/vs
#   2. npm-pack the TextMate stack (vscode-textmate, vscode-oniguruma)
#   3. bump pkg_manifest.version to the new monaco release
#   The build guard in pkgs/monaco-editor/build.sh then enforces that the declared
#   version always matches the vendored monaco release.
#
# The hand-rolled bridge (textmate/monaco-editor-textmate.js) is never
# replaced — it is not an npm artifact.

REPO_ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )
VENDOR_DIR="${REPO_ROOT}/pkgs/monaco-editor/assets/vendor"
CONFIG="${REPO_ROOT}/pkgs/monaco-editor/config.yml"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

cd "${WORK}"

# --- 1. monaco-editor (drives the package version) ---
npm pack monaco-editor@latest >/dev/null
tar -xzf monaco-editor-*.tgz
NEW_MONACO=$(python3 -c "import json;print(json.load(open('package/package.json'))['version'])")
CUR_MONACO=$(python3 -c "import json;print(json.load(open('${VENDOR_DIR}/monaco/package.json'))['version'])")

if [ "${NEW_MONACO}" = "${CUR_MONACO}" ]; then
    echo "monaco-editor already at ${CUR_MONACO} — nothing to refresh"
    exit 0
fi

rm -rf "${VENDOR_DIR}/monaco/vs"
mkdir -p "${VENDOR_DIR}/monaco"
cp -R package/min/vs "${VENDOR_DIR}/monaco/vs"
cp package/package.json "${VENDOR_DIR}/monaco/package.json"

# --- 2. TextMate stack (refreshed alongside, does not drive the version) ---
npm pack vscode-textmate@latest >/dev/null
tar -xzf vscode-textmate-*.tgz
rm -f "${VENDOR_DIR}/textmate/vscode-textmate/"*
cp package/release/main.js "${VENDOR_DIR}/textmate/vscode-textmate/main.js"
cp package/types/vscode-textmate.d.ts "${VENDOR_DIR}/textmate/vscode-textmate/vscode-textmate.d.ts"
cp package/package.json "${VENDOR_DIR}/textmate/vscode-textmate/package.json"
cp package/LICENSE.md "${VENDOR_DIR}/textmate/vscode-textmate/LICENSE.md"

npm pack vscode-oniguruma@latest >/dev/null
tar -xzf vscode-oniguruma-*.tgz
rm -rf "${VENDOR_DIR}/textmate/vscode-oniguruma"
mkdir -p "${VENDOR_DIR}/textmate/vscode-oniguruma/release"
cp package/release/main.js "${VENDOR_DIR}/textmate/vscode-oniguruma/release/main.js"
cp package/release/onig.wasm "${VENDOR_DIR}/textmate/vscode-oniguruma/release/onig.wasm"
cp package/package.json "${VENDOR_DIR}/textmate/vscode-oniguruma/package.json"
cp package/LICENSE.txt "${VENDOR_DIR}/textmate/vscode-oniguruma/LICENSE.txt"

# --- 3. bump the package version to the vendored monaco release ---
cd "${REPO_ROOT}"
pkg-tool bump monaco-editor --version "${NEW_MONACO}"

echo
echo "monaco-editor vendor refreshed: monaco ${CUR_MONACO} -> ${NEW_MONACO}"
echo "TextMate stack updated in step 2; the hand-rolled bridge is untouched."
echo "Review the diff, then commit:"
echo "  git add pkgs/monaco-editor && git commit -m 'monaco-editor: vendor monaco-editor ${NEW_MONACO}' && git push"
