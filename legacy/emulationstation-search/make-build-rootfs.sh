#!/usr/bin/env bash
# ============================================================
#  Turn the RetroPie base image into a Docker build rootfs.
#
#  Why: EmulationStation on a Pi 2/3 is built with -DRPI=On, which
#  links bcm_host / vchiq_arm from /opt/vc -- Raspberry Pi firmware
#  libraries that plain Debian armhf simply does not ship. Building
#  inside the actual target rootfs is the only way to get a binary
#  that both links and runs.
#
#  Produces the docker image:  retropie-rootfs:buster-armhf
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# MSYS_NO_PATHCONV above stops Git Bash rewriting *container* paths, but it
# also stops it translating *host* paths -- and docker needs a real Windows
# path for build contexts and volume sources. Convert explicitly.
winpath() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}


BUILD_ROOT="${BUILD_ROOT:-D:/RetroPi2-build}"
IMG_NAME="${IMG_NAME:-retropie-buster-4.8-rpi2_3_zero2w.img}"
TAG="retropie-rootfs:buster-armhf"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$HERE")"
IMAGE_DIR="${IMAGE_DIR:-$BUILD_ROOT/image}"
IMG_HOST="$IMAGE_DIR/$IMG_NAME"

if docker image inspect "$TAG" >/dev/null 2>&1; then
    echo "==> $TAG already exists (delete it to rebuild)"
    exit 0
fi

[ -f "$IMG_HOST" ] || { echo "Base image not found: $IMG_HOST" >&2; exit 1; }

mkdir -p "$BUILD_ROOT"

echo "==> Extracting root filesystem from the base image"
docker run --rm --privileged     -v "$(winpath "$IMAGE_DIR"):/img:ro"     -v "$(winpath "$BUILD_ROOT"):/out"     -v "$(winpath "$HERE"):/scripts:ro"     alpine sh /scripts/extract-rootfs-inner.sh "$IMG_NAME"

echo "==> Importing as $TAG"
docker import --platform linux/arm/v7 "$BUILD_ROOT/rootfs.tar" "$TAG"
rm -f "$BUILD_ROOT/rootfs.tar"

echo "==> Verifying"
docker run --rm --platform linux/arm/v7 "$TAG" \
    sh -c 'uname -m; ls /opt/vc/include/bcm_host.h && echo BCM_HOST_PRESENT'
