# The widget's settings dialog changes the gaps and the focus border of the
# running script, and the border hides on maximized and fullscreen windows.
kpackagetool6 -t Plasma/Applet --install "$MT_ROOT/widget" >/dev/null 2>&1
plasmashell --no-respawn >"$MT_OUT/plasmashell.log" 2>&1 & sleep 12
kwrite >/dev/null 2>&1 & sleep 2.5
konsole >/dev/null 2>&1 & sleep 2.5
kg "MindTile: Tiles layout" 1.5; dump tiles-default
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    panels()[0].addWidget('com.github.morvoso.mindtile');" >/dev/null 2>&1
sleep 3
# Right click the widget at the end of the panel.
mti move 1896 1056 sleep 200 click right sleep 1500
shot settings-1-menu
mti move 1800 952 sleep 200 click left sleep 3000
shot settings-2-dialog
dump dialog-open
# Gap between tiles: 20
mti move 1405 616 click left sleep 300 press 29 key 30 release 29 sleep 200 key 3 sleep 200 key 11 sleep 300
# Gap at the screen edge: 0
mti move 1405 652 click left sleep 300 press 29 key 30 release 29 key 11 sleep 300
# Border width: 6
mti move 1405 728 click left sleep 300 press 29 key 30 release 29 key 7 sleep 300
# Use the accent color: off, then open the color picker
mti move 1408 760 click left sleep 500 move 1420 792 click left sleep 2500
shot settings-3-picker
# Type #e91e63 in the picker, then OK in the picker and in the settings window.
mti move 1496 930 click left sleep 300 press 29 key 30 release 29 sleep 200 press 42 key 4 release 42 sleep 100 key 18 sleep 100 key 10 sleep 100 key 2 sleep 100 key 18 sleep 100 key 7 sleep 100 key 4 sleep 500
shot settings-4-typed
mti move 1452 996 click left sleep 1500
shot settings-5-changed
mti move 1680 1000 click left sleep 3000
echo "== mindtilerc" >&2; grep style "$XDG_CONFIG_HOME/mindtilerc" >&2
dump after-ok
mti move 400 500 click left sleep 1500
shot settings-6-applied
dump kwrite-active
sleep 2
kg "MindTile: Columns layout" 1.5
echo "== mindtilerc after more saves" >&2; grep style "$XDG_CONFIG_HOME/mindtilerc" >&2
kg "MindTile: Floating layout" 1.5
kg "Window Maximize" 1.5; dump maximized
kg "Window Maximize" 1.5; kg "Window Fullscreen" 1.5; dump fullscreen
kg "Window Fullscreen" 1.5; dump normal-again
