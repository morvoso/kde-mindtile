# The installer from a checkout: script, widget, keys; then uninstall.
own() { gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.getGlobalShortcutsByKey $1 | grep -o "^(\[('[^']*'" >&2; }
MT=$((0x10000000 | 0x54))
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript mindtile
echo "== install" >&2
"$MT_ROOT/install.sh" >&2
echo "== state" >&2
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded mindtile >&2
kpackagetool6 -t Plasma/Applet --show com.github.morvoso.mindtile | head -2 >&2
own $MT
echo "== reinstall" >&2
"$MT_ROOT/install.sh" --no-tray >&2
echo "== uninstall" >&2
"$MT_ROOT/install.sh" --uninstall >&2
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded mindtile >&2
own $MT
ls "$XDG_DATA_HOME/kwin/scripts" "$XDG_DATA_HOME/plasma/plasmoids" >&2
