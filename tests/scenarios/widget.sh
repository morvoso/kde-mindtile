# The panel widget in its own window: it follows layout changes made with
# the shortcuts, and switches the layout itself.
kpackagetool6 -t Plasma/Applet --install "$MT_ROOT/widget" >&2
QT_QUICK_BACKEND=software plasmawindowed com.github.morvoso.mindtile > "$MT_OUT/widget.log" 2>&1 & sleep 6
dump start; shot 1-widget-floating
kg "MindTile: Tiles layout" 2.5; shot 2-widget-tiles
kg "MindTile: Floating layout" 2.5; shot 3-widget-floating-again
