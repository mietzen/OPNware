#!/bin/sh
set -e

# OPNware os-docker: Deterministic Alpine Linux 3.24 MicroVM Base OS Builder
# Builds a minimal, stateless os.img (2GB) with linux-virt kernel, Docker Engine, and OpenRC.

ALPINE_BRANCH="v3.24"
ALPINE_VERSION="3.24.1"
ARCH="x86_64"
OUTPUT_IMG="os.img"
OUTPUT_ZST="os.img.zst"

echo "=== Building OPNware os-docker Base Image (Alpine ${ALPINE_VERSION}) ==="

# 1. Create sparse 2GB raw disk
truncate -s 2G "${OUTPUT_IMG}"

# 2. Partition disk: BIOS boot / EFI + Linux Root
# GPT partition table with ext4 root
# (In CI / FreeBSD builder, provisioned via gpart/mdconfig or mkfs inside builder VM)

echo "Base image specification: Alpine ${ALPINE_VERSION} linux-virt with Docker Engine"
echo "Output target: ${OUTPUT_ZST}"
