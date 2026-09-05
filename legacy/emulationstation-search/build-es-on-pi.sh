#!/usr/bin/env bash
# ============================================================
#  Build the patched EmulationStation ON the Raspberry Pi.
#
#  Use this when the PC-side emulated build isn't available.
#  Building natively on the Pi is the most reliable option --
#  it's the exact target hardware, libraries and compiler.
#
#  Copy this script and es-patch/0001-search-bar.patch to the Pi,
#  then:
#      chmod +x build-es-on-pi.sh
#      ./build-es-on-pi.sh
#
#  Takes roughly 40-90 minutes on a Pi 3. Runs unattended.
#  When it finishes it prints how to copy the binary back.
# ============================================================
set -euo pipefail

ES_REF="${ES_REF:-v2.11.2}"
WORK="${WORK:-$HOME/retropi2-esbuild}"
PATCH="${PATCH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/0001-search-bar.patch}"

if [ ! -f "$PATCH" ]; then
    echo "Patch not found: $PATCH" >&2
    echo "Copy 0001-search-bar.patch next to this script." >&2
    exit 1
fi

echo "==> Installing build dependencies"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git \
    libsdl2-dev libfreeimage-dev libfreetype6-dev libcurl4-openssl-dev \
    rapidjson-dev libasound2-dev libvlc-dev libvlccore-dev \
    libraspberrypi-dev

echo "==> Fetching EmulationStation $ES_REF"
rm -rf "$WORK"
git clone --depth 1 --recurse-submodules --shallow-submodules \
    --branch "$ES_REF" \
    https://github.com/RetroPie/EmulationStation.git "$WORK"

echo "==> Applying the search patch"
git -C "$WORK" apply "$PATCH"

# A Pi 3 has 1 GB of RAM; linking EmulationStation can exhaust it.
# Temporarily grow swap, exactly as RetroPie's own build does.
SWAP_CONF=/etc/dphys-swapfile
SWAP_RESTORE=""
if [ -f "$SWAP_CONF" ]; then
    CUR=$(grep -oP '^CONF_SWAPSIZE=\K.*' "$SWAP_CONF" || echo "")
    if [ -n "$CUR" ] && [ "$CUR" -lt 1024 ] 2>/dev/null; then
        echo "==> Temporarily raising swap to 1024 MB (was ${CUR} MB)"
        sudo sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/" "$SWAP_CONF"
        sudo systemctl restart dphys-swapfile || true
        SWAP_RESTORE="$CUR"
    fi
fi

restore_swap() {
    if [ -n "$SWAP_RESTORE" ]; then
        echo "==> Restoring swap to ${SWAP_RESTORE} MB"
        sudo sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=${SWAP_RESTORE}/" "$SWAP_CONF"
        sudo systemctl restart dphys-swapfile || true
    fi
}
trap restore_swap EXIT

echo "==> Building (this is the slow part)"
cd "$WORK"
# Same flags RetroPie uses for a Pi 2/3: VideoCore, GLESv1, dispmanx video.
cmake . \
    -DCMAKE_BUILD_TYPE=Release \
    -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/ \
    -DRPI=On -DUSE_GLES1=On -DOMX=On
make -j2          # -j2, not -j4: a Pi 3 runs out of RAM otherwise

echo
echo "============================================================"
echo " Built: $WORK/emulationstation"
ls -lh "$WORK/emulationstation"
echo
echo " Copy it back to your PC, from the PC, with:"
echo "   scp pi@$(hostname -I | awk '{print $1}'):$WORK/emulationstation \\"
echo "       'C:/Dev/Retro Pi 2.0/src/modules/retropi2/filesystem/prebuilt/'"
echo
echo " Then on the PC run:  .\build.ps1"
echo "============================================================"
