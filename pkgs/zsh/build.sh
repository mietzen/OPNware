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
SRC_REPO=$(yq -r '.build_config.src_repo' "${CONFIG}")

echo "::group::Install pkg-repo-tools"
python3.11 -m venv .venv
source .venv/bin/activate
pip install "file://${GH_WS}/${REPO_DIR}/pkg-tool"
echo "::endgroup::"

echo "Compiling ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"

echo "::group::Git checkout repository"
git clone --depth=1 --branch zsh-${VERSION} ${SRC_REPO} ${GH_WS}/src
echo "::endgroup::"

echo "::group::Build Binary"
cd "${GH_WS}/src"
./Util/preconfig
./configure --prefix=/opt/zsh \
    --enable-function-subdirs \
    --enable-multibyte \
    --enable-zsh-secure-free \
    --enable-gdbm \
    --enable-pcre \
    --enable-cap \
    --with-tcsetpgrp
gmake
gmake install DESTDIR=${GH_WS}/dist/pkg
echo "::endgroup::"
cd "${GH_WS}"

# Create Directories
mkdir -p "${GH_WS}/dist/pkg/opt/bin"

# Link Binary
cd "${GH_WS}/dist/pkg/opt/bin/"
ln -s "../${PKG_NAME}/bin/${PKG_NAME}" "${PKG_NAME}"
cd "${GH_WS}"

# Copy License
cp "${GH_WS}/src/LICENCE" "${GH_WS}/dist/pkg/opt/${PKG_NAME}/LICENSE"
chmod 0644 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/LICENSE"

# Provide a link to the Source Code
cat <<EOF > "${GH_WS}/dist/pkg/opt/${PKG_NAME}/SOURCE"
This software is licensed under the proprietary ZSH license.
You may obtain a copy of the source code at:
https://www.zsh.org/pub/zsh-${VERSION}.tar.xz
EOF
chmod 0644 "${GH_WS}/dist/pkg/opt/${PKG_NAME}/SOURCE"

# Create BSD distribution pkg
cd "${GH_WS}/dist"

# Create Manifest
pkg-tool create-manifest "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"

# Create Package
tar -cf "${PKG_NAME}-${VERSION}.pkg" \
    --zstd \
    --absolute-paths \
    --owner=0 \
    --group=0 \
    -s '|^pkg||' \
    +COMPACT_MANIFEST +MANIFEST $(find pkg -type f) $(find pkg -type l)

# Create Packagesite Info
pkg-tool create-packagesite-info ./+COMPACT_MANIFEST

# Cleanup
rm -rf "${GH_WS}/dist/+MANIFEST" "${GH_WS}/dist/+COMPACT_MANIFEST" "${GH_WS}/dist/pkg"
