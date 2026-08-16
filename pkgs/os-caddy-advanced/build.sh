#!/bin/bash
set -e

ARCH="${1}"
ABI="${2}"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG="${SCRIPT_DIR}/config.yml"
REPO_ROOT=$( cd "${SCRIPT_DIR}/../.." && pwd )
DIST_ROOT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"

echo "Building os-caddy-advanced - ARCH: ${ARCH} - ABI: ${ABI}"

mkdir -p "${DIST_ROOT}/dist/pkg/usr/local"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local"
cp -R "${SCRIPT_DIR}/src/." "${DIST_ROOT}/dist/pkg/usr/local/"

# The rc.d script is staged usr/local-prefixed in the plugin tree (everything
# else in src is /usr/local-relative); relocate it to the payload's
# usr/local/etc/rc.d and drop the double-prefixed copy.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d"
install -m 0755 "${SCRIPT_DIR}/src/usr/local/etc/rc.d/caddy" \
    "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/caddy"
rm -rf "${DIST_ROOT}/dist/pkg/usr/local/usr/local"

# Our own MIT license for the plugin code.
mkdir -p "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy-advanced"
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy-advanced"
cp "${SCRIPT_DIR}/LICENSE" "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy-advanced/LICENSE"
chmod 0644 "${DIST_ROOT}/dist/pkg/usr/local/share/doc/os-caddy-advanced/LICENSE"

# The Monaco/TextMate tree ships in the shared monaco-editor package
# (both plugins depend on it) — it is NOT copied into plugin payloads, so
# pkg never sees duplicate file ownership. See docs/design/shared-editor-vendor.md.

find "${DIST_ROOT}/dist/pkg/usr/local" -type d -exec chmod 0755 {} +
find "${DIST_ROOT}/dist/pkg/usr/local" -type f -exec chmod 0644 {} +
# The rc.d script must stay executable after the normalization above.
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/etc/rc.d/caddy"
# The module management script is run directly by the pkg trigger (no
# configd php wrapper), so it must be executable.
chmod 0755 "${DIST_ROOT}/dist/pkg/usr/local/opnsense/scripts/OPNsense/CaddyAdvanced/modules.php"

cd "${DIST_ROOT}/dist"
pkg-tool pack "${CONFIG}" --abi "${ABI}" --arch "${ARCH}"
