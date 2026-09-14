#!/bin/bash
# Builds the Meta+wheel KWin effect against the installed KWin.
#   effect/build.sh OUTDIR   writes OUTDIR/mindtile_wheel.so
# Needs g++, pkg-config, Qt 6 and the KWin headers (kwin on Arch, kwin-devel
# on Fedora, kwin-dev on Debian and Ubuntu).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/../build/effect}
mkdir -p "$out"
moc=""
for candidate in /usr/lib/qt6/moc /usr/lib/qt6/libexec/moc /usr/libexec/qt6/moc /usr/lib64/qt6/libexec/moc "$(command -v moc-qt6 || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then moc=$candidate; break; fi
done
[ -n "$moc" ] || { echo "moc (Qt 6) not found" >&2; exit 1; }
[ -f /usr/include/kwin/effect/effect.h ] || { echo "KWin headers not found (/usr/include/kwin)" >&2; exit 1; }
command -v g++ >/dev/null || { echo "g++ not found" >&2; exit 1; }

includes="-I/usr/include/kwin $(for d in /usr/include/KF6/*/; do printf -- '-I%s ' "$d"; done) $(pkg-config --cflags-only-I Qt6Core Qt6Gui Qt6DBus)"
# shellcheck disable=SC2086
"$moc" $includes "$here/mindtile_wheel.cpp" -o "$out/mindtile_wheel.moc"
# shellcheck disable=SC2086
g++ -std=c++20 -O2 -fPIC -shared -fvisibility=hidden \
    -DQT_NO_KEYWORDS \
    -I"$out" -I"$here" $includes \
    $(pkg-config --cflags Qt6Core Qt6Gui Qt6DBus) \
    "$here/mindtile_wheel.cpp" -o "$out/mindtile_wheel.so" \
    -lkwin $(pkg-config --libs Qt6Core Qt6Gui Qt6DBus) -lKF6CoreAddons
echo "$out/mindtile_wheel.so"
