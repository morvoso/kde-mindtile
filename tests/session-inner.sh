#!/bin/bash
# Inside the headless session: helpers for the scenario files.
kg() { qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; sleep ${2:-0.6}; }
load() {
    local id
    id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$1" "$2")
    qdbus6 org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run
}
shot() { spectacle -b -n -f -o "$MT_OUT/$1.png" >/dev/null 2>&1; sleep 1.5; }
mti() { "$MT_ROOT/build/tools/mtinput" "$@"; }
dump() { echo "== $1" >&2; kg "Probe: dump" 0.3; }
sleep 2
load "$MT_ROOT/tests/probe/contents/ui/main.qml" probe
load "$MT_ROOT/package/contents/ui/main.qml" mindtile
sleep 1
source "$MT_SCENARIO"
sleep 1
