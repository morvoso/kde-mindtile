#!/bin/bash
# Runs MindTile in a headless KWin with its own config directory and takes
# screenshots of each layout. Usage: tests/kwin-session.sh [scenario] [outdir]
# The scenario file is sourced inside the session; see tests/scenarios/.
set -u
here=$(cd "$(dirname "$0")" && pwd)
scenario=${1:-$here/scenarios/basic.sh}
out=${2:-$here/../build/session}
rm -rf "$out" && mkdir -p "$out"/{config,cache,state,data}
printf "[Icons]\nTheme=breeze\n" > "$out/config/kdeglobals"
export MT_ROOT=$(cd "$here/.." && pwd) MT_OUT=$out MT_SCENARIO=$scenario
timeout ${MT_TIMEOUT:-120} dbus-run-session -- env \
    XDG_CONFIG_HOME="$out/config" XDG_CACHE_HOME="$out/cache" XDG_STATE_HOME="$out/state" XDG_DATA_HOME="$out/data" \
    QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="js.debug=true;qml.debug=true" \
    QT_QPA_PLATFORM=wayland KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 \
    kwin_wayland --virtual --width ${MT_WIDTH:-1920} --height ${MT_HEIGHT:-1080} --output-count ${MT_OUTPUTS:-1} --no-lockscreen \
    --exit-with-session "$here/session-inner.sh" > "$out/kwin.log" 2>&1
grep -h "PROBE\|MindTile\|main.qml\|engine.js" "$out/kwin.log"
