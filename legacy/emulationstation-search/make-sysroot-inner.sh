#!/usr/bin/env bash
# Runs inside a privileged debian container.
# Extracts the RetroPie root filesystem to /sysroot for cross-compiling.
set -euo pipefail

IMG_NAME="$1"

apt-get update -qq
apt-get install -y -qq --no-install-recommends util-linux fdisk symlinks rsync >/dev/null

cp "/img/$IMG_NAME" /tmp/base.img

# Mount by byte offset: loop partition nodes don't propagate into containers.
START=$(sfdisk -d /tmp/base.img | sed -n 's#^.*base\.img2 *: *start= *\([0-9][0-9]*\).*#\1#p')
[ -n "$START" ] || { echo "could not read partition 2 start" >&2; exit 1; }
OFFSET=$((START * 512))
echo "root partition at byte $OFFSET"

mkdir -p /mnt/rp
mount -o ro,loop,offset="$OFFSET" /tmp/base.img /mnt/rp

# Only the parts a cross-compile needs -- headers, libraries, pkg-config
# and the VideoCore firmware libs. Copying the whole rootfs would drag in
# gigabytes of emulators and BIOS files for nothing.
echo "copying sysroot..."
rsync -a --numeric-ids \
    /mnt/rp/usr/include/ /sysroot/usr/include/
rsync -a --numeric-ids \
    /mnt/rp/usr/lib/ /sysroot/usr/lib/
rsync -a --numeric-ids \
    /mnt/rp/lib/ /sysroot/lib/
mkdir -p /sysroot/opt/vc
rsync -a --numeric-ids \
    /mnt/rp/opt/vc/ /sysroot/opt/vc/
if [ -d /mnt/rp/usr/share/pkgconfig ]; then
    mkdir -p /sysroot/usr/share/pkgconfig
    rsync -a --numeric-ids /mnt/rp/usr/share/pkgconfig/ /sysroot/usr/share/pkgconfig/
fi

umount /mnt/rp
rm -f /tmp/base.img

# Absolute symlinks like /usr/lib/.../libfoo.so -> /lib/.../libfoo.so.1
# point at the HOST outside a chroot. Rewrite them relative to the sysroot
# or the linker silently resolves them wrong (or not at all).
echo "relativising symlinks..."
symlinks -cr /sysroot >/dev/null 2>&1 || true
DANGLING=$(symlinks -r /sysroot 2>/dev/null | grep -c '^dangling' || true)
echo "sysroot ready (dangling symlinks: ${DANGLING:-0})"
ls -l /sysroot/opt/vc/lib/libbcm_host.so >/dev/null && echo "bcm_host present"
