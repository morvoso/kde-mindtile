# Two screens: a maximised window entering the tiling, columns parked off
# their screen, a tile sent to the other screen, and the mode kept across a
# restart of the script.
kg0() { qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; sleep ${2:-0.8}; }
kwrite >/dev/null 2>&1 & sleep 2.5
kg0 "Window Maximize" 1
konsole >/dev/null 2>&1 & sleep 2.5
kcalc >/dev/null 2>&1 & sleep 2.5
dolphin >/dev/null 2>&1 & sleep 3
dump floating-kwrite-maximised
kg "MindTile: Columns layout" 1.5; dump columns; shot 1-columns
kg "MindTile: Focus left" 0.5; kg "MindTile: Focus left" 0.5; kg "MindTile: Focus left" 1.5; dump columns-first; shot 2-columns-first
kg0 "Window to Next Screen" 1.5; dump kwrite-next-screen; shot 3-next-screen
kg "MindTile: Floating layout" 1.5; dump floating; shot 4-floating
kg "MindTile: Tiles layout" 1.5; dump tiles-before-restart
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript mindtile; sleep 1
load "$MT_ROOT/package/contents/ui/main.qml" mindtile; sleep 1.5
konsole >/dev/null 2>&1 & sleep 2.5
dump tiles-after-restart-new-konsole; shot 5-after-restart
