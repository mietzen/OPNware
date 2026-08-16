#!/bin/bash
set -euo pipefail

# OPNware — bump the shared monaco-editor package to a new release.
#
# The monaco-editor payload is built in CI (pkgs/monaco-editor/build.sh
# npm-packs the pinned release, applies the CSP worker patch, packs). A
# version bump here is therefore the ENTIRE update: the daily check-updates
# flow (update.yml, abi_arch 'vendor') calls this script, which bumps
# pkg_manifest.version; the next CI build fetches that release. The PR is
# NOT auto-merged — the human reviews the diff, that review IS the safety
# gate (the codemod fails the build if the patch patterns change).
#
# Usage: ./scripts/refresh-editor.sh <version>
#   (no args = bump to the latest npm release)

REPO_ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )
CONFIG="${REPO_ROOT}/pkgs/monaco-editor/config.yml"

NEW_MONACO="${1:-}"
if [ -z "${NEW_MONACO}" ]; then
    NEW_MONACO=$(npm view monaco-editor version)
fi

CUR_MONACO=$(pkg-tool dump "${CONFIG}" pkg_manifest.version | sed -E 's/_[0-9]+$//')
if [ "${NEW_MONACO}" = "${CUR_MONACO}" ]; then
    echo "monaco-editor already at ${CUR_MONACO} — nothing to bump"
    exit 0
fi

cd "${REPO_ROOT}"
pkg-tool bump monaco-editor --version "${NEW_MONACO}"

echo
echo "monaco-editor bumped: ${CUR_MONACO} -> ${NEW_MONACO}"
echo "The CI build fetches, patches and packs the new release. Review the diff,"
echo "then commit:"
echo "  git add pkgs/monaco-editor && git commit -m 'monaco-editor: bump to ${NEW_MONACO}' && git push"
