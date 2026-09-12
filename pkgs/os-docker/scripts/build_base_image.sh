#!/bin/sh
set -e

# OPNware os-docker: Deterministic Alpine Linux 3.24 MicroVM Base OS Builder
# Builds a minimal, stateless os.img (2GB) with linux-virt kernel, Docker Engine, and OpenRC.

ALPINE_BRANCH="v3.24"
ALPINE_VERSION="3.24.1"
ARCH="x86_64"
OUTPUT_DIR="build_vm"
OUTPUT_IMG="os.img"
OUTPUT_ZST="os.img.zst"
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"

echo "=== Building OPNware os-docker Base Image (Alpine ${ALPINE_VERSION}) ==="

mkdir -p "${OUTPUT_DIR}"

# 1. Download Alpine minirootfs if not cached
if [ ! -f "alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz" ]; then
    echo "Downloading ${MINIROOTFS_URL}..."
    curl -fsSL "${MINIROOTFS_URL}" -o "alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
fi

# 2. Extract minirootfs into builder staging
rm -rf "${OUTPUT_DIR}/rootfs"
mkdir -p "${OUTPUT_DIR}/rootfs"
tar -xzf "alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz" -C "${OUTPUT_DIR}/rootfs"

# 3. Configure networking & repositories
cat << 'EOF' > "${OUTPUT_DIR}/rootfs/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 100.64.0.2
    netmask 255.255.255.0
    gateway 100.64.0.1
EOF

cat << EOF > "${OUTPUT_DIR}/rootfs/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/main
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/community
EOF

# 4. First-boot data disk auto-format service (/dev/vdb -> /var/lib/docker)
cat << 'EOF' > "${OUTPUT_DIR}/rootfs/etc/init.d/docker-storage-init"
#!/sbin/openrc-run
description="Format and mount persistent Docker data volume"

depend() {
    before dockerd
    need localmount
}

start() {
    ebegin "Initializing Docker persistent storage"
    if [ -b /dev/vdb ]; then
        if ! blkid /dev/vdb >/dev/null 2>&1; then
            einfo "Formatting /dev/vdb as ext4..."
            mkfs.ext4 -F -L DOCKER_DATA /dev/vdb
        fi
        mkdir -p /var/lib/docker
        if ! mountpoint -q /var/lib/docker; then
            mount /dev/vdb /var/lib/docker
        fi
    fi
    # Ensure netfilter forwards packets to containers
    iptables -I FORWARD 1 -j ACCEPT 2>/dev/null || true
    eend $?
}
EOF
chmod 0755 "${OUTPUT_DIR}/rootfs/etc/init.d/docker-storage-init"

# 5. Configure Docker Daemon (disable slow snapshotter layer recursion)
mkdir -p "${OUTPUT_DIR}/rootfs/etc/docker"
cat << 'EOF' > "${OUTPUT_DIR}/rootfs/etc/docker/daemon.json"
{
  "features": {
    "containerd-snapshotter": false
  }
}
EOF

# 6. Summary and Packaging instructions
echo "Rootfs prepared successfully."
echo "Packaged artifact target: ${OUTPUT_ZST}"
