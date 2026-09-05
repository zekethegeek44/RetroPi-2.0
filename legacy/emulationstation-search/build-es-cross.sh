#!/usr/bin/env bash
# ============================================================
#  Cross-build the patched EmulationStation for a Pi 2/3.
#
#  cmake runs natively on x86 against the RetroPie root filesystem
#  as a sysroot. This exists because Docker's ARM emulation breaks
#  cmake's file(GLOB) on this machine -- see README.
#
#  Produces: src/modules/retropi2/filesystem/prebuilt/emulationstation
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

winpath() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$HERE")"
BUILD_ROOT="${BUILD_ROOT:-D:/RetroPi2-build}"
ES_SRC="${ES_SRC:-$BUILD_ROOT/es}"
SYSROOT="${SYSROOT:-$BUILD_ROOT/sysroot}"
IMG_NAME="${IMG_NAME:-retropie-buster-4.8-rpi2_3_zero2w.img}"

# ---- 1. sysroot ------------------------------------------------
if [ ! -d "$SYSROOT/opt/vc/include" ]; then
    echo "==> Building sysroot from the RetroPie image"
    mkdir -p "$SYSROOT"
    docker run --rm --privileged \
        -v "$(winpath "$BUILD_ROOT/image"):/img:ro" \
        -v "$(winpath "$SYSROOT"):/sysroot" \
        -v "$(winpath "$HERE"):/scripts:ro" \
        debian:bookworm bash /scripts/make-sysroot-inner.sh "$IMG_NAME"
else
    echo "==> Reusing sysroot at $SYSROOT"
fi

# ---- 2. toolchain image ----------------------------------------
echo "==> Building cross toolchain image"
docker build -f "$(winpath "$HERE")/Dockerfile.esbuild-cross" \
    -t es-build:cross "$(winpath "$HERE")"

# ---- 3. compile -------------------------------------------------
echo "==> Cross-compiling EmulationStation"
docker run --rm \
    -v "$(winpath "$ES_SRC"):/src" \
    -v "$(winpath "$SYSROOT"):/sysroot:ro" \
    -v "$(winpath "$HERE"):/scripts:ro" \
    -e SYSROOT=/sysroot \
    -w /src es-build:cross bash -euxc '
        export PKG_CONFIG_SYSROOT_DIR=/sysroot
        export PKG_CONFIG_LIBDIR=/sysroot/usr/lib/arm-linux-gnueabihf/pkgconfig:/sysroot/usr/lib/pkgconfig:/sysroot/usr/share/pkgconfig
        rm -rf build-cross
        cmake -S . -B build-cross \
            -DCMAKE_TOOLCHAIN_FILE=/scripts/armhf-toolchain.cmake \
            -DCMAKE_BUILD_TYPE=Release \
            -DFREETYPE_INCLUDE_DIRS=/sysroot/usr/include/freetype2/ \
            -DRPI=On -DUSE_GLES1=On -DOMX=On
        cmake --build build-cross -j"$(nproc)"
    '

OUT="$PROJECT/src/modules/retropi2/filesystem/prebuilt"
mkdir -p "$OUT"
# ES's CMake writes the binary to the source root.
cp "$ES_SRC/emulationstation" "$OUT/emulationstation"
chmod +x "$OUT/emulationstation"
echo "==> Wrote $OUT/emulationstation"
file "$OUT/emulationstation"
