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

echo "::group::Install pkg-tool"
pip install "file://${GH_WS}/${REPO_DIR}/pkg-tool"
echo "::endgroup::"

echo "Redistributing ${PKG_NAME} - ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"
cd "${GH_WS}/dist"

pkg-tool redistribute-pkg "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
