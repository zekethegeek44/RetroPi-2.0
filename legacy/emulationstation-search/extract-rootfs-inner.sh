#!/bin/sh
# Runs inside a privileged alpine container.
# Mounts the RetroPie image's root partition and tars it to /out/rootfs.tar.
set -eu

IMG_NAME="$1"

apk add --no-cache util-linux e2fsprogs tar >/dev/null

cp "/img/$IMG_NAME" /tmp/base.img

# Partition 2 is the Raspbian root filesystem. Mount by byte offset:
# losetup -P partition nodes (loopNp2) don't propagate into the container,
# so /dev/loopNp2 never appears and the mount fails with
# "Can't lookup blockdev".
START=$(sfdisk -d /tmp/base.img | sed -n 's#^.*base\.img2 *: *start= *\([0-9][0-9]*\).*#\1#p')
if [ -z "$START" ]; then
    echo "could not determine root partition start; sfdisk said:" >&2
    sfdisk -d /tmp/base.img >&2
    exit 1
fi
OFFSET=$((START * 512))
echo "root partition: sector $START, byte offset $OFFSET"

mkdir -p /mnt/rp
mount -o ro,loop,offset="$OFFSET" /tmp/base.img /mnt/rp

# Sanity check: this is the whole reason we build in the RetroPie rootfs.
ls -l /mnt/rp/opt/vc/include/bcm_host.h

echo "tarring root filesystem..."
tar -C /mnt/rp -cf /out/rootfs.tar .

umount /mnt/rp
rm -f /tmp/base.img
echo "rootfs.tar written"
