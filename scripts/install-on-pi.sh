#!/usr/bin/env bash
# ============================================================
#  Install Retro Pi 2.0 onto a running Raspberry Pi.
#
#  Does everything the image build does, but to a live system --
#  so an existing Raspberry Pi OS install becomes Retro Pi 2.0
#  without reflashing and without losing your user account.
#
#  Requires: Raspberry Pi OS Trixie (Debian 13), 64-bit, on a Pi 4.
#
#  Run it on the Pi, one line, nothing to download first:
#      curl -sSL https://raw.githubusercontent.com/zekethegeek44/RetroPi-2.0/main/install | sudo bash
#
#  Or from a checkout:
#      sudo bash scripts/install-on-pi.sh
#
#  Safe to re-run. Existing configs are backed up as *.retropi2.bak
#  and never silently overwritten.
# ============================================================
set -uo pipefail

REPO_URL="${RP2_REPO_URL:-https://github.com/zekethegeek44/RetroPi-2.0.git}"

# Work out where the project files are. When this script is piped
# straight from the web (curl ... | sudo bash) there is no repo on disk
# yet, so fetch one. That is what makes the one-line install work
# without cloning anything by hand first.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    REPO_DIR=""
fi
if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/src/modules/retropi2" ]; then
    echo "==> Fetching Retro Pi 2.0"
    command -v git >/dev/null 2>&1 || {
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
    }
    REPO_DIR="/opt/retropi2/repo"
    mkdir -p "$(dirname "$REPO_DIR")"
    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" fetch --depth 1 -q origin main &&         git -C "$REPO_DIR" reset --hard -q origin/main
    else
        rm -rf "$REPO_DIR"
        git clone --depth 1 -q "$REPO_URL" "$REPO_DIR"
    fi
fi
FSROOT="$REPO_DIR/src/modules/retropi2/filesystem/root"
FSHOME="$REPO_DIR/src/modules/retropi2/filesystem/home/pi"
BOOTDIR="/boot/firmware"

# The account Kodi and the games run as. Defaults to whoever invoked
# sudo, which is almost always right.
RP2_USER="${RP2_USER:-${SUDO_USER:-pi}}"

say()  { echo ""; echo "==> $*"; }
warn() { echo "!!  $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo"
id "$RP2_USER" >/dev/null 2>&1 || die "user '$RP2_USER' does not exist"
[ -d "$FSROOT" ] || die "can't find the project files (looked in $FSROOT)"

USER_HOME="$(getent passwd "$RP2_USER" | cut -d: -f6)"
[ -n "$USER_HOME" ] || die "can't determine home directory for $RP2_USER"

say "Installing Retro Pi 2.0 for user '$RP2_USER' (home: $USER_HOME)"

# ---- preflight ------------------------------------------------
ARCH="$(dpkg --print-architecture)"
[ "$ARCH" = "arm64" ] || warn "expected arm64, found '$ARCH' -- continuing anyway"
grep -q trixie /etc/os-release || warn "this was built for Trixie; your OS differs"
[ -d "$BOOTDIR" ] || { BOOTDIR="/boot"; warn "using /boot (older layout)"; }

export DEBIAN_FRONTEND=noninteractive

# ---- 1. packages ----------------------------------------------
say "Installing packages (this is the slow part)"
apt-get update || die "apt-get update failed -- check the network"

apt-get install -y --no-install-recommends \
    kodi kodi-bin kodi-data kodi-repository-kodi kodi-eventclients-kodi-send \
    || die "Kodi install failed"

apt-get install -y --no-install-recommends retroarch libretro-core-info \
    || die "RetroArch install failed"

# Only the cores Debian actually ships for arm64; the rest come from the
# libretro buildbot in step 7.
for core in libretro-nestopia libretro-gambatte libretro-mgba \
            libretro-desmume libretro-bsnes-mercury-accuracy; do
    apt-get install -y --no-install-recommends "$core" \
        || warn "core '$core' unavailable, skipping"
done

apt-get install -y --no-install-recommends \
    whiptail rsync unzip ca-certificates cifs-utils nfs-common git \
    samba samba-common-bin avahi-daemon \
    bluez bluez-tools \
    cec-utils udisks2 exfatprogs ntfs-3g \
    || warn "some optional packages failed"

# ---- 2. remember which user this is ---------------------------
say "Recording the target user"
mkdir -p /etc/retropi2
echo "$RP2_USER" > /etc/retropi2/user

# ---- 3. our scripts -------------------------------------------
say "Installing scripts"
for f in retropi2-firstboot retropi2-install-addons retropi2-install-cores \
         retropi2-update retropi2-usb-mount; do
    if [ -f "$FSROOT/usr/local/bin/$f" ]; then
        install -m 0755 "$FSROOT/usr/local/bin/$f" "/usr/local/bin/$f"
        echo "    /usr/local/bin/$f"
    fi
done

# ---- 4. systemd units -----------------------------------------
say "Installing services"
for u in retropi2-kodi retropi2-firstboot retropi2-addons; do
    src="$FSROOT/etc/systemd/system/$u.service"
    [ -f "$src" ] || continue
    # The units ship with User=pi; rewrite for the real account.
    sed -e "s/^User=pi$/User=$RP2_USER/" \
        -e "s/^Group=pi$/Group=$RP2_USER/" \
        -e "s#^Environment=HOME=/home/pi\$#Environment=HOME=$USER_HOME#" \
        "$src" > "/etc/systemd/system/$u.service"
    echo "    $u.service"
done
if [ -f "$FSROOT/etc/systemd/system/retropi2-usb-mount@.service" ]; then
    install -m 0644 "$FSROOT/etc/systemd/system/retropi2-usb-mount@.service" \
        /etc/systemd/system/
fi
if [ -f "$FSROOT/etc/udev/rules.d/99-retropi2-usb.rules" ]; then
    install -m 0644 "$FSROOT/etc/udev/rules.d/99-retropi2-usb.rules" \
        /etc/udev/rules.d/
fi
systemctl daemon-reload

# ---- 5. Kodi as the shell -------------------------------------
say "Configuring Kodi to run as the shell"
# GBM needs direct GPU access; input needs evdev. Without these Kodi
# starts with no picture and no controller.
usermod -aG video,render,input,audio,tty,dialout,plugdev "$RP2_USER"
systemctl set-default multi-user.target

KODI_HOME="$USER_HOME/.kodi"
mkdir -p "$KODI_HOME/userdata" "$KODI_HOME/addons"

GUI="$KODI_HOME/userdata/guisettings.xml"
if [ ! -f "$GUI" ]; then
    cat > "$GUI" <<'EOF'
<settings version="2">
    <setting id="services.devicename">RetroPi2</setting>
    <setting id="services.webserver">true</setting>
    <setting id="services.webserverport">8080</setting>
    <setting id="services.webserverusername">kodi</setting>
    <setting id="services.webserverpassword">retropi2</setting>
    <setting id="services.esenabled">true</setting>
    <setting id="services.zeroconf">true</setting>
    <setting id="services.upnp">true</setting>
    <setting id="input.enablejoystick">true</setting>
</settings>
EOF
fi

FAV="$KODI_HOME/userdata/favourites.xml"
if [ ! -f "$FAV" ]; then
    cat > "$FAV" <<'EOF'
<favourites>
    <favourite name="Update Retro Pi 2.0">RunScript(script.retropi2.update)</favourite>
</favourites>
EOF
fi

if [ -d "$FSHOME/.kodi/addons/script.retropi2.update" ]; then
    cp -a "$FSHOME/.kodi/addons/script.retropi2.update" "$KODI_HOME/addons/"
fi
chown -R "$RP2_USER":"$RP2_USER" "$KODI_HOME"

# ---- 6. directories -------------------------------------------
say "Creating games and media folders"
ROMS="$USER_HOME/roms"
MEDIA="$USER_HOME/media"
mkdir -p "$MEDIA"/movies "$MEDIA"/tv
for sys in nes snes megadrive gb gba n64 psx nds atari2600 atari5200 gbc arcade; do
    mkdir -p "$ROMS/$sys"
done
chown -R "$RP2_USER":"$RP2_USER" "$ROMS" "$MEDIA"

# ---- 7. sharing and peripherals -------------------------------
say "Setting up file sharing, Bluetooth and USB automount"
if [ -f "$FSROOT/etc/samba/retropi2-shares.conf" ]; then
    # Point the shares at the real user's folders.
    sed -e "s#/home/pi/#$USER_HOME/#g" \
        -e "s/force user = pi/force user = $RP2_USER/" \
        -e "s/force group = pi/force group = $RP2_USER/" \
        "$FSROOT/etc/samba/retropi2-shares.conf" \
        > /etc/samba/retropi2-shares.conf

    if [ -f /etc/samba/smb.conf ]; then
        [ -f /etc/samba/smb.conf.retropi2.bak ] || \
            cp /etc/samba/smb.conf /etc/samba/smb.conf.retropi2.bak
        grep -q "map to guest" /etc/samba/smb.conf || \
            sed -i '/^\[global\]/a \   map to guest = Bad User' /etc/samba/smb.conf
        grep -q "retropi2-shares.conf" /etc/samba/smb.conf || \
            printf '\n# Retro Pi 2.0 shares\ninclude = /etc/samba/retropi2-shares.conf\n' \
                >> /etc/samba/smb.conf
    fi
    systemctl enable --now smbd 2>/dev/null || warn "could not start smbd"
    systemctl enable --now nmbd 2>/dev/null || true
fi
systemctl enable --now avahi-daemon 2>/dev/null || true
systemctl enable --now bluetooth   2>/dev/null || true
mkdir -p /media
udevadm control --reload-rules 2>/dev/null || true

# ---- 8. boot tuning -------------------------------------------
say "Tuning boot"
CONFIGTXT="$BOOTDIR/config.txt"
if [ -f "$CONFIGTXT" ] && ! grep -q "Retro Pi 2.0" "$CONFIGTXT"; then
    cp "$CONFIGTXT" "$CONFIGTXT.retropi2.bak"
    cat >> "$CONFIGTXT" <<'EOF'

# ---- Retro Pi 2.0 ----
disable_splash=1
boot_delay=0
gpu_mem=320
EOF
fi

for svc in triggerhappy.service man-db.timer \
           apt-daily.timer apt-daily-upgrade.timer; do
    systemctl disable "$svc" 2>/dev/null || true
done

# ---- 9. skin, addons and cores --------------------------------
say "Downloading Kodi add-ons and emulator cores (several minutes)"
sudo -u "$RP2_USER" HOME="$USER_HOME" /usr/local/bin/retropi2-install-addons \
    || warn "add-on install had problems -- Kodi will use the default skin"
sudo -u "$RP2_USER" HOME="$USER_HOME" /usr/local/bin/retropi2-install-cores \
    || warn "core download had problems"

mkdir -p /var/lib/retropi2
chown "$RP2_USER":"$RP2_USER" /var/lib/retropi2
# The first-boot wizard is for fresh images; this machine is already
# set up, so don't ambush the user with it on next boot.
touch "$BOOTDIR/retropi2-firstboot-done" 2>/dev/null || true
touch /var/lib/retropi2/firstboot-done
chown "$RP2_USER":"$RP2_USER" /var/lib/retropi2/firstboot-done 2>/dev/null || true

# ---- 10. enable Kodi ------------------------------------------
say "Enabling Kodi"
systemctl enable retropi2-kodi.service || die "could not enable Kodi service"

echo ""
echo "============================================================"
echo " Retro Pi 2.0 installed."
echo ""
echo "   user:    $RP2_USER"
echo "   games:   $ROMS"
echo "   media:   $MEDIA"
echo "   share:   \\\\$(hostname)\\roms   (from Windows Explorer)"
echo ""
echo " Start Kodi now with:"
echo "     sudo systemctl start retropi2-kodi"
echo " or reboot:"
echo "     sudo reboot"
echo "============================================================"
