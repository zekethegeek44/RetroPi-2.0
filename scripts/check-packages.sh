#!/usr/bin/env bash
# ============================================================
#  Preflight: do all the packages we apt-install actually exist?
#
#  Written after two wasted build cycles. Checking availability via
#  packages.debian.org/.../download is useless -- it returns HTTP 200
#  for packages that do not exist. This queries the real apt index.
#
#  Usage: bash scripts/check-packages.sh
#  Exit 0 if every package resolves, 1 otherwise.
# ============================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$HERE")"
CHROOT="$PROJECT/src/modules/retropi2/start_chroot_script"
MODCFG="$PROJECT/src/modules/retropi2/config"

# Packages named on apt-get install lines (continuations included),
# minus flags and shell variables.
pkgs=$(
    sed -n '/apt-get install/,/[^\\]$/p' "$CHROOT" \
    | tr ' \t' '\n\n' \
    | sed 's/\\$//' \
    | grep -E '^[a-z0-9][a-z0-9+.-]+$' \
    | grep -vE '^(apt|apt-get|get|install|y|no|recommends|true|fi|do|done|then|else|core|echo|for|in)$'
)

# Plus the core list from the module config.
# shellcheck disable=SC1090
set -a; . "$MODCFG"; set +a
pkgs="$pkgs ${RP2_CORES:-}"

# Unique, sorted.
pkgs=$(printf '%s\n' $pkgs | sort -u | tr '\n' ' ')

echo "==> Checking $(printf '%s\n' $pkgs | wc -w) packages against Debian Trixie"
echo

docker run --rm -i debian:trixie bash -s -- $pkgs <<'INNER'
set -u
apt-get update -qq >/dev/null 2>&1
missing=0
for p in "$@"; do
    ver=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
    if [ -z "$ver" ] || [ "$ver" = "(none)" ]; then
        printf '  MISSING  %s\n' "$p"
        missing=$((missing + 1))
    else
        printf '  ok       %-34s %s\n' "$p" "$ver"
    fi
done
echo
if [ "$missing" -gt 0 ]; then
    echo "RESULT: $missing package(s) do not exist -- fix these before building."
    exit 1
fi
echo "RESULT: all packages resolve"
INNER
