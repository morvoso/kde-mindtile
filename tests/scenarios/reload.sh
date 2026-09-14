# The script is reloaded while the windows are tiles: going back to Floating
# must still put them where they were, and the old instance must not react
# to the windows any more.
kwrite >/dev/null 2>&1 & sleep 2.5
konsole >/dev/null 2>&1 & sleep 2.5
kcalc >/dev/null 2>&1 & sleep 3
dump floating
kg "MindTile: Tiles layout" 1.5; dump tiles
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript mindtile; sleep 1
load "$MT_ROOT/package/contents/ui/main.qml" mindtile; sleep 1.5
kg "MindTile: Columns layout" 1.5; dump columns-after-reload
kg "MindTile: Floating layout" 1.5; dump floating-after-reload; shot reload-floating
