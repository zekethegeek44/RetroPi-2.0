#!/usr/bin/env bash
# ============================================================
#  Verify a built Retro Pi 2.0 image by mounting it.
#
#  Build logs say what the build *tried* to do; this says what
#  actually ended up on the card. It has already caught real bugs
#  (a settings file left root-owned because the path was a symlink).
#
#  Usage: bash scripts/verify-image.sh [path-to-.img]
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

DIST_DIR="${DIST_DIR:-D:/RetroPi2-build/dist}"
IMG="${1:-}"

if [ -z "$IMG" ]; then
    IMG=$(ls -t "$DIST_DIR"/RetroPi2-*.img 2>/dev/null | head -1) || true
fi
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "No image found. Pass one as an argument." >&2; exit 1; }

IMG_DIR="$(cd "$(dirname "$IMG")" && pwd)"
IMG_FILE="$(basename "$IMG")"
echo "==> Verifying $IMG_FILE"

winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

docker run --rm --privileged \
    -v "$(winpath "$IMG_DIR"):/d:ro" \
    alpine sh -s "$IMG_FILE" <<'INNER'
set -eu
IMG="/d/$1"
apk add --no-cache util-linux >/dev/null 2>&1

# Mount by byte offset: loop partition nodes don't appear inside containers.
BOOT_START=$(sfdisk -d "$IMG" | sed -n 's#^.*img1 *: *start= *\([0-9][0-9]*\).*#\1#p')
ROOT_START=$(sfdisk -d "$IMG" | sed -n 's#^.*img2 *: *start= *\([0-9][0-9]*\).*#\1#p')
[ -n "$ROOT_START" ] || { echo "could not read partition table"; exit 1; }

mkdir -p /mnt/r
mount -o ro,loop,offset=$((ROOT_START * 512)) "$IMG" /mnt/r

fail=0
chk() { # label, path
    if [ -e "/mnt/r$2" ]; then printf '  ok      %s\n' "$1"
    else printf '  MISSING %s  (%s)\n' "$1" "$2"; fail=$((fail+1)); fi
}

echo "--- identity ---"
printf '  hostname: %s\n' "$(cat /mnt/r/etc/hostname 2>/dev/null || echo '?')"
printf '  user pi:  %s\n' "$(grep -c '^pi:' /mnt/r/etc/passwd 2>/dev/null || echo 0)"

echo "--- Kodi ---"
chk "kodi-standalone binary" /usr/bin/kodi-standalone
chk "kodi.bin"               /usr/lib/aarch64-linux-gnu/kodi/kodi.bin
chk "kodi service"           /etc/systemd/system/retropi2-kodi.service
chk "kodi service enabled"   /etc/systemd/system/multi-user.target.wants/retropi2-kodi.service

echo "--- RetroArch ---"
chk "retroarch binary" /usr/bin/retroarch
printf '  bundled cores: %s\n' "$(ls /mnt/r/usr/lib/aarch64-linux-gnu/libretro/*.so 2>/dev/null | wc -l)"

echo "--- our scripts ---"
chk "firstboot wizard"  /usr/local/bin/retropi2-firstboot
chk "addon installer"   /usr/local/bin/retropi2-install-addons
chk "core installer"    /usr/local/bin/retropi2-install-cores
chk "wizard enabled"    /etc/systemd/system/multi-user.target.wants/retropi2-firstboot.service
chk "downloads enabled" /etc/systemd/system/multi-user.target.wants/retropi2-addons.service
chk "state dir"         /var/lib/retropi2

echo "--- directories ---"
chk "roms"   /home/pi/roms
chk "media"  /home/pi/media
printf '  rom systems: %s\n' "$(ls /mnt/r/home/pi/roms 2>/dev/null | tr '\n' ' ')"
printf '  home owner:  %s\n' "$(stat -c '%u:%g' /mnt/r/home/pi 2>/dev/null || echo '?')"

echo "--- first-run wizard suppressed ---"
if [ -e /mnt/r/etc/systemd/system/userconfig.service ]; then
    printf '  ok      userconfig masked\n'
else
    printf '  note    userconfig.service not present (fine if the base lacks it)\n'
fi

echo "--- leftovers that should NOT ship ---"
for junk in /home/pi/.gitkeep /.gitkeep; do
    if [ -e "/mnt/r$junk" ]; then printf '  LEAKED  %s\n' "$junk"; fail=$((fail+1)); fi
done

umount /mnt/r

if [ -n "$BOOT_START" ]; then
    mkdir -p /mnt/b
    mount -o ro,loop,offset=$((BOOT_START * 512)) "$IMG" /mnt/b
    echo "--- boot config ---"
    printf '  cmdline: %s\n' "$(cat /mnt/b/cmdline.txt 2>/dev/null | head -c 200)"
    printf '  gpu_mem: %s\n' "$(grep -m1 '^gpu_mem' /mnt/b/config.txt 2>/dev/null || echo 'not set')"
    grep -q 'disable_splash=1' /mnt/b/config.txt 2>/dev/null \
        && echo '  ok      splash disabled' || echo '  MISSING splash setting'
    umount /mnt/b
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: all checks passed"
else
    echo "RESULT: $fail problem(s) found"
fi
exit 0
INNER
