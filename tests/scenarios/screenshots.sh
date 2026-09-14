# Store screenshots: a Breeze Dark Plasma desktop with the widget in the
# tray, in each layout, plus the widget's popup. Output in $MT_OUT/shots.
mkdir -p "$MT_OUT/shots"
load "$MT_ROOT/tests/shots/main.qml" shots
# A copy of the widget that can open its popup (see tests/shots/open-popup.qml).
rm -rf "$MT_OUT/widget-shot" && cp -r "$MT_ROOT/widget" "$MT_OUT/widget-shot"
qml="$MT_OUT/widget-shot/contents/ui/main.qml"
sed -i '$ d' "$qml" && cat "$MT_ROOT/tests/shots/open-popup.qml" >> "$qml"
kpackagetool6 -t Plasma/Applet --install "$MT_OUT/widget-shot" >/dev/null 2>&1
plasma-apply-colorscheme BreezeDark >/dev/null 2>&1
kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark
appletsrc="$MT_OUT/config/plasma-org.kde.plasma.desktop-appletsrc"

# First run creates the default panel; put the widget in its tray.
plasmashell --no-respawn >"$MT_OUT/plasmashell.log" 2>&1 & sleep 12
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    panels().forEach(function (p) {
        p.widgets('org.kde.plasma.systemtray').forEach(function (t) {
            t.currentConfigGroup = ['General'];
            t.writeConfig('extraItems', String(t.readConfig('extraItems', '')).split(',').concat(['com.github.morvoso.mindtile']));
            t.reloadConfig();
        });
    });" >/dev/null
sleep 3
kquitapp6 plasmashell >/dev/null 2>&1; sleep 3

# Clear the task manager's pinned launchers.
python3 - "$appletsrc" <<'PY'
import re, subprocess, sys
path = sys.argv[1]
group = None
for line in open(path):
    m = re.match(r"^\[(.*)\]$", line.strip())
    if m:
        group = re.findall(r"\[?([^\]\[]+)\]?", m.group(1))
        continue
    groups = lambda g: sum((["--group", x] for x in g), [])
    if line.strip() in ("plugin=org.kde.plasma.icontasks", "plugin=org.kde.plasma.taskmanager"):
        subprocess.run(["kwriteconfig6", "--file", path] + groups(group + ["Configuration", "General"]) + ["--key", "launchers", ""])
PY
plasmashell --no-respawn >>"$MT_OUT/plasmashell.log" 2>&1 & sleep 12

cd "$MT_ROOT"
dolphin "$MT_ROOT" >/dev/null 2>&1 & sleep 3
kwrite "$MT_ROOT/README.md" >/dev/null 2>&1 & sleep 3
konsole --hold -e bash -c "cd '$MT_ROOT' && node --test tests/ 2>&1 | tail -n 30" >/dev/null 2>&1 & sleep 4
kcalc >/dev/null 2>&1 & sleep 3
kg "Shots: place" 1.5; shot shots/raw-floating
kg "MindTile: Tiles layout" 2; shot shots/raw-tiles
kg "MindTile: Columns layout" 2; kg "MindTile: Focus left" 1; kg "MindTile: Cycle size" 2; shot shots/raw-columns
kg "MindTile: Tiles layout" 2
printf "[Shot]\nopen=1\n" > "$MT_OUT/config/mindtile-shot"; sleep 0.8
shot shots/raw-widget-early
shot shots/raw-widget
