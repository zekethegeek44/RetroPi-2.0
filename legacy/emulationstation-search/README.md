# Legacy: EmulationStation search bar

This was the original approach — a patched EmulationStation with a
gamepad-navigable on-screen keyboard and a cross-system name search,
built for a RetroPie/Buster image on a Pi 2/3.

It was shelved when the project moved to **Kodi as the shell** on
Raspberry Pi OS Trixie (Pi 4). Kodi has its own search, so the patch is
no longer needed — but it works and is kept here rather than thrown away.

**Status:** the patch compiles cleanly against EmulationStation
`v2.11.2` and applies cleanly to a fresh checkout. It was never run on
hardware.

- `0001-search-bar.patch` — the EmulationStation changes:
  - `GuiOnScreenKeyboard` (new) — d-pad navigable keyboard
  - a substring name filter in `FileFilterIndex`, applied in `showFile()`
- `build-es-cross.sh` — cross-build on x86 (preferred; the emulated
  build is broken by a cmake `file(GLOB)` bug under qemu)
- `build-es-on-pi.sh` — build natively on a Pi; slowest to set up but
  the most reliable
- the rest are the supporting toolchain and sysroot scripts

To revive it you would also need the old RetroPie base image and the
Buster-era `src/config`; see git history.
