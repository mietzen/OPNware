#!/bin/bash
set -e

# Setup Environment Variables
ARCH="${1}"
ABI="${2}"
GH_WS="${GITHUB_WORKSPACE}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
PKG_NAME=$(pkg-tool dump "${CONFIG}" redistribute.name)

echo "Redistributing ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"
cd "${GH_WS}/dist"

pkg-tool redistribute-pkg "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
