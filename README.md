# Retro Pi 2.0

A custom media-and-games image for the **Raspberry Pi 4 / 400**, built to be
flashed straight to an SD card.

It boots directly into **Kodi** with a dashboard-style interface — rows for
Continue Watching, Recently Added, Movies, TV and Games — with **RetroArch**
behind it so games launch from the same place as everything else.

| | |
|---|---|
| **One interface** | Kodi is the shell. No desktop, no separate game frontend to switch between. |
| **Movies and TV** | Jellyfin, Plex or a plain network share. Set up on first boot. |
| **Games with box art** | Advanced Kodi Launcher scans your ROMs, fetches artwork, and launches RetroArch straight into the game. |
| **First-boot wizard** | WiFi, media server, SSH and timezone handled on screen. |
| **Fast, quiet boot** | Background services stripped, no console spam, no splash delay. |
| **Updates over WiFi** | Kodi → Favourites → *Update Retro Pi 2.0*. No reflashing, no SSH. |
| **Drag-and-drop games** | `\\retropi2\roms` in Windows Explorer. USB sticks auto-mount too. |
| **TV remote works** | HDMI-CEC, so Kodi is driven by the remote you already have. |
| **Phone remote** | Kodi web interface on `:8080` — use the official Kodi app. |
| **Controllers** | Bluetooth enabled, plus ~440 gamepad profiles so pads work unmapped. |

---

## Two ways to install

**Already have a Raspberry Pi OS install?** One line on the Pi, nothing to
download first:

```bash
curl -sSL https://raw.githubusercontent.com/zekethegeek44/RetroPi-2.0/main/install | sudo bash
```

That converts a stock Raspberry Pi OS Trixie (64-bit) install in place: Kodi as
the shell, RetroArch, sharing, updates. **Your user account is kept** — the
installer reads it from `$SUDO_USER` and records it in `/etc/retropi2/user`, so
nothing assumes the account is called `pi`. Safe to re-run; existing configs are
backed up as `*.retropi2.bak`.

**Starting from a blank card?** Build the image below and flash it. It does the
same thing unattended on first boot — no SSH, no terminal.

---

## Building the image

You need **Docker Desktop** running.

```powershell
.\build.ps1
```

The result lands in `D:\RetroPi2-build\dist\RetroPi2-<date>.img`. Flash it with
[Raspberry Pi Imager](https://www.raspberrypi.com/software/) or balenaEtcher.

```powershell
.\build.ps1 -Clean      # throw away the workspace and start over
```

Everything large lives on `D:\RetroPi2-build\` — the base image, the build
workspace, and the finished image. `C:` is nearly full and Docker's own VM disk
is already there.

> **Flashing erases the card.** Use a spare SD card if you have one: your
> existing setup stays intact and you can swap back in seconds.

---

## The stack, and why

| Piece | Version | Why |
|---|---|---|
| Raspberry Pi OS **Trixie** (Debian 13), 64-bit Lite | 2026-06-18 | Current, live mirrors, and 64-bit is meaningfully faster on a Pi 4 |
| **Kodi** | 21.2 | From apt — nothing compiled |
| **RetroArch** | 1.20 | From apt; 5 cores from Debian, the rest from the libretro buildbot on first boot |
| **Arctic Horizon 2** | 0.8.30~omega | The dashboard skin: vertical hubs, horizontal widget rows |
| **Advanced Kodi Launcher** | latest | Game scanning, artwork, RetroArch launching |
| **Jellyfin for Kodi** | 2.1.0 | Media server client |

### Why not RetroPie?

The project started on RetroPie 4.8, which is Debian **Buster**. Buster ships
**Kodi 17.6 — from 2017**. The Jellyfin addon and every modern skin need Kodi
19 or newer, so Buster couldn't deliver the interface this image is for.

The catch is that it's one or the other:

| Base | Kodi | RetroPie |
|---|---|---|
| Buster | 17.6 | ✅ full support, prebuilt binaries |
| Bullseye | 19.1 | ❌ not supported by RetroPie |
| Trixie | **21.2** | ⚠️ no official binaries |

So the image uses RetroArch directly instead of RetroPie. Same emulator cores
underneath, same ROMs — you just configure controllers in RetroArch rather than
getting RetroPie's auto-configuration.

Everything installs from `apt` or as a prebuilt addon. **Nothing is compiled
during the build**, which is what keeps it fast and reliable.

---

## Layout

```
build.ps1                       Windows entrypoint
scripts/
  check-packages.sh             preflight: do these packages exist? (~30s)
  verify-image.sh               mount a built image and check its contents
src/
  config                        CustomPiOS global build config
  modules/retropi2/
    config                      feature switches
    start_chroot_script         everything done to the image
    filesystem/root/
      usr/local/bin/
        retropi2-firstboot        the setup wizard
        retropi2-install-addons   Kodi skin/addons (runs on first boot)
        retropi2-install-cores    emulator cores (runs on first boot)
      etc/systemd/system/         kodi / wizard / addon units
  image/                        (empty — base image lives on D:)
legacy/emulationstation-search/ the original RetroPie search-bar work
```

Feature switches live in `src/modules/retropi2/config` — set any to `no` to
leave that part of the image alone.

---

## Checking your work

Two scripts exist because the build is slow and the logs lie by omission.

```bash
bash scripts/check-packages.sh     # before building
bash scripts/verify-image.sh       # after building
```

`check-packages.sh` resolves every package we install against the real Debian
index. **Do not** check availability by fetching
`packages.debian.org/<suite>/<arch>/<pkg>/download` — that returns HTTP 200 for
packages that do not exist, which is how `kodi-gbm`, `kodi-standalone` and
eight non-existent `libretro-*` cores got into an earlier revision.

`verify-image.sh` loop-mounts the finished `.img` and reports what is actually
on it. A build log tells you what the build *tried* to do; this tells you what
shipped. It has already caught a settings file left root-owned because the path
it was written through was a symlink.

---

## Why addons install on first boot, not at build time

Kodi addons have dependency trees that have to be resolved against live
repositories, and the build runs in an emulated chroot with no sensible way to
drive Kodi. So `retropi2-install-addons` runs once on the Pi, where there's a
real network:

1. Pulls Kodi's official Omega index (~2300 addons)
2. Installs the skin from its GitHub `omega` branch, resolving dependencies
   recursively
3. Fetches the two dependencies the official repo doesn't carry
   (`script.texturemaker`, `resource.font.robotocjksc`)
4. Installs Advanced Kodi Launcher, its RetroArch plugin, and Jellyfin
5. Sets the skin

`retropi2-install-cores` runs alongside it and pulls the emulator cores.
Debian only packages five usable ones for arm64 — nothing for Genesis, N64,
PS1 or arcade — so the rest come from libretro's buildbot, which carries 212
cores for aarch64. The image ships the Debian five so it is playable with no
network at all.

It is **best-effort on purpose**. If a repo has moved or the network is down it
logs the failure and lets Kodi start on the stock Estuary skin, rather than
leaving a black screen on the TV. Re-run it any time:

```bash
sudo systemctl start retropi2-addons
journalctl -u retropi2-addons
```

---

## Getting games and media on

**From Windows** — open Explorer and go to:

```
\\retropi2\roms          games, one folder per console
\\retropi2\media         local movies and TV
\\retropi2\usb           anything plugged into a USB port
```

Guest access, no password. That is deliberate — it is what makes
drag-and-drop work with no setup, and it matches what RetroPie did.
**It suits a home LAN and nothing else.** On a shared or public network,
delete `/etc/samba/retropi2-shares.conf` and use `scp` instead.

**From a USB stick** — plug it in. `retropi2-usb-mount` (a udev rule plus a
templated systemd unit) mounts it under `/media/<label>`, owned by `pi`, and
unmounts it on removal. FAT, exFAT, NTFS and ext are handled; the boot device
is explicitly skipped.

Keeping ROMs on a USB drive is also the tidiest way to make them survive any
future reflash.

---

## Updating without reflashing

Kodi home screen → **Favourites → Update Retro Pi 2.0**. It updates four things:

| | What |
|---|---|
| **system** | `apt` packages — Kodi, RetroArch, the OS |
| **scripts** | this project, pulled from its GitHub repo |
| **cores** | libretro emulator cores |
| **addons** | the Kodi skin and add-ons |

Same thing over SSH, with finer control:

```bash
sudo retropi2-update              # everything
sudo retropi2-update --cores      # just emulator cores
sudo retropi2-update --system     # just apt
tail -f /var/log/retropi2-update.log
```

**`apt upgrade` is the default, not `full-upgrade`.** Full upgrade is offered as
a separate, explicitly-confirmed choice because it can install a new major
version of Kodi, which sometimes breaks the skin — and a Pi has no snapshot to
roll back to. There is no unattended auto-update for the same reason: you would
find out it broke when the TV showed a broken interface.

Because updates come from the GitHub repo, fixes made to this project reach the
Pi without a reflash. Only things baked in at build time — the base OS version,
partition layout, boot config — still need a new image.

Note that `--force` is passed to the core and add-on installers during an
update. Both normally skip anything already present, so without it an update
would silently do nothing.

---

## After flashing

1. Boot it. The setup wizard appears on screen — WiFi, media server, timezone.
2. It reboots into Kodi. First boot is slower: it's downloading addons.
3. Copy ROMs to `/home/pi/roms/<system>/` (the wizard shows you how).
4. In Kodi: **Add-ons → Advanced Kodi Launcher** to scan games and get box art.

Default login is `pi` / `raspberry`, and Kodi's web remote is `kodi` /
`retropi2` on port 8080. Both are fine on a home network and should be
changed on any other kind.

---

## Notes and limits

- **Untested on hardware.** The image builds and its contents are verified by
  mounting it, but nothing here has been booted on a real Pi 4. Expect the
  first flash to be a feedback round.
- **The skin is the least certain piece.** It installs from a GitHub branch
  rather than Kodi's official repo, and manually-placed addons sometimes need
  enabling in Kodi's UI. Estuary is the automatic fallback.
- **AKL needs configuring once** — pointing it at `/home/pi/roms` and RetroArch
  — through its own UI. That can't sensibly be pre-seeded.
- **cmake's `file(GLOB)` is broken under Docker's ARM emulation** on this
  machine: it returns zero results for directories that demonstrably have
  files, which breaks compiler detection and makes `find_package()` silently
  miss libraries. Updating the qemu binfmt handlers doesn't fix it. This is why
  the build installs everything from packages instead of compiling, and why the
  legacy EmulationStation build had to cross-compile.
- CustomPiOS quirks worth knowing:
  - its entrypoint hardcodes `DIST_PATH=/distro`, so `/distro` must be the
    project's **`src/`** directory, not the repo root
  - for any board other than `raspberrypiarmhf` it **overwrites**
    `BASE_ZIP_IMG` with a glob over `$BASE_IMAGE_PATH/*.{zip,7z,xz}`, so set
    `BASE_IMAGE_PATH` and leave the compressed image in place
  - it ends with a `chmod 777` that fails on a Windows bind mount *after* the
    image is written correctly — trust the artifact, not the exit code
