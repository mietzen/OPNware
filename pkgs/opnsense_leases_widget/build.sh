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

echo "::group::Install pkg-tool"
pip install "file://${GH_WS}/${REPO_DIR}/pkg-tool"
echo "::endgroup::"

echo "::group::Install pnpm"
npm install -g pnpm@latest-10
echo "::endgroup::"

echo "Building ${PKG_NAME} - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${GH_WS}/dist"
chmod 0755 "${GH_WS}/dist"

echo "::group::Git Checkout Repository"
git clone --branch "${VERSION}" "${SRC_REPO}" "${GH_WS}/src"
echo "::endgroup::"

# Create Directories for Packaging
mkdir -p "${GH_WS}/dist/usr/local/opnsense/www/js/widgets"
mkdir -p "${GH_WS}/dist/tmp/opnsense_leases_widget"
mkdir -p "${GH_WS}/dist/usr/local/share/licenses/opnsense_leases_widget"

# Copying files
cp -r "${GH_WS}/src/Leases.js" "${GH_WS}/dist/usr/local/opnsense/www/js/widgets/"
chmod 0755 "${GH_WS}/dist/usr/local/opnsense/www/js/widgets/Leases.js"
cp -r "${GH_WS}/src/Core.xml" "${GH_WS}/dist/tmp/opnsense_leases_widget/"
chmod 0755 "${GH_WS}/dist/tmp/opnsense_leases_widget/Core.xml"

# Copy License
cp "${GH_WS}/src/LICENSE" "${GH_WS}/dist/usr/local/share/licenses/${PKG_NAME}/"
chmod 0644 "${GH_WS}/dist/usr/local/share/licenses/${PKG_NAME}/LICENSE"

# Provide Source Code Link
cat <<EOF > "${GH_WS}/dist/usr/local/share/licenses/${PKG_NAME}/SOURCE"
This software is licensed under the GNU General Public License v3.0.
You may obtain a copy of the source code at:
https://github.com/jbaconsult/opnsense_stuff/archive/refs/main.tar.gz
EOF
chmod 0644 "${GH_WS}/dist/usr/local/share/licenses/${PKG_NAME}/SOURCE"

# Create BSD distribution pkg
cd "${GH_WS}/dist"

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
