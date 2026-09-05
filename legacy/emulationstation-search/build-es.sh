#!/usr/bin/env bash
# ============================================================
#  Build the patched EmulationStation (search bar).
#
#  Modes:
#    check  fast native x86 compile-check -- catches code errors
#    arm    the shipping armhf binary, built inside the RetroPie
#           rootfs so it links against the real Pi libraries
#
#  Produces (arm):  src/modules/retropi2/filesystem/prebuilt/emulationstation
#
#  Kept separate from the image build on purpose: this compile is
#  slow under emulation, so the result is cached and image rebuilds
#  stay quick.
# ============================================================
set -euo pipefail

# Git Bash rewrites container paths like /src into C:/Program Files/Git/src.
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


HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$HERE")"

ES_SRC="${ES_SRC:-D:/RetroPi2-build/es}"
ES_REF="${ES_REF:-v2.11.2}"
MODE="${1:-arm}"

if [ ! -d "$ES_SRC" ]; then
    echo "==> Cloning EmulationStation $ES_REF"
    git clone --depth 1 --recurse-submodules --shallow-submodules \
        --branch "$ES_REF" \
        https://github.com/RetroPie/EmulationStation.git "$ES_SRC"
    echo "==> Applying Retro Pi 2.0 search patch"
    git -C "$ES_SRC" apply "$PROJECT/es-patch/0001-search-bar.patch"
fi

case "$MODE" in
  check)
    echo "==> Native compile-check"
    docker build --build-arg BASE=debian:bookworm \
        -f "$(winpath "$HERE")/Dockerfile.esbuild" -t es-build:amd64 "$(winpath "$HERE")"
    docker run --rm -v "$(winpath "$ES_SRC"):/src" -w /src es-build:amd64 bash -euxc '
        rm -rf build-check
        cmake -S . -B build-check -DCMAKE_BUILD_TYPE=Release -DGL=On \
              -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/
        cmake --build build-check -j"$(nproc)"
    '
    # Remove the x86 artifact so it can never be confused with the
    # armhf binary -- both land at the same path.
    rm -f "$ES_SRC/emulationstation"
    echo "==> Compile-check passed."
    ;;

  arm)
    echo "==> Preparing armhf rootfs from the RetroPie image"
    bash "$HERE/make-build-rootfs.sh"

    echo "==> Building armhf toolchain image"
    docker build --platform linux/arm/v7 \
        -f "$(winpath "$HERE")/Dockerfile.esbuild-arm" -t es-build:armhf "$(winpath "$HERE")"

    # These are exactly the flags RetroPie uses for a Pi 2/3:
    #   RPI=On        Raspberry Pi memory/audio paths
    #   USE_GLES1=On  GLESv2 performs badly on VideoCore IV
    #   OMX=On        dispmanx video previews
    echo "==> Compiling (emulated ARM -- this takes a long time)"
    docker run --rm --platform linux/arm/v7 \
        -v "$(winpath "$ES_SRC"):/src" -w /src es-build:armhf bash -euxc '
        rm -rf build-arm
        cmake -S . -B build-arm -DCMAKE_BUILD_TYPE=Release \
              -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/ \
              -DRPI=On -DUSE_GLES1=On -DOMX=On
        cmake --build build-arm -j"$(nproc)"
    '

    # ES's CMake writes the binary to the SOURCE root, not the build dir.
    # It has to land in the module's filesystem/ tree, because that is the
    # only thing CustomPiOS copies into the chroot (as /filesystem).
    OUT="$PROJECT/src/modules/retropi2/filesystem/prebuilt"
    mkdir -p "$OUT"
    cp "$ES_SRC/emulationstation" "$OUT/emulationstation"
    chmod +x "$OUT/emulationstation"
    echo "==> Wrote src/modules/retropi2/filesystem/prebuilt/emulationstation"
    file "$OUT/emulationstation" 2>/dev/null || true
    ;;

  *) echo "usage: $0 [check|arm]" >&2; exit 2 ;;
esac
