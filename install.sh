#!/usr/bin/env bash
# MindTile installer for KDE Plasma 6.
#
#   curl -fsSL https://raw.githubusercontent.com/morvoso/kde-mindtile/main/install.sh | bash
#
# Options (with curl, pass them as: ... | bash -s -- --no-keys):
#   --no-keys     leave Plasma's Meta+T, Meta+arrows and Meta+Shift+Left/Right alone
#   --no-tray     install the widget but don't add it to the system tray
#   --uninstall   remove the script and the widget, give Plasma its keys back
#
# Everything goes into ~/.local/share. No root needed.
set -euo pipefail

REPO="morvoso/kde-mindtile"
BRANCH="main"
SCRIPT_ID="mindtile"
WIDGET_ID="com.github.morvoso.mindtile"

claim_keys=1
tray=1
uninstall=0
for arg in "$@"; do
    case "$arg" in
        --no-keys) claim_keys=0 ;;
        --no-tray) tray=0 ;;
        --uninstall) uninstall=1 ;;
        -h|--help) sed -n '2,12p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for tool in kpackagetool6 kwriteconfig6 qdbus6 gdbus; do
    command -v "$tool" >/dev/null || die "$tool not found. MindTile needs KDE Plasma 6."
done
qdbus6 org.kde.KWin /KWin >/dev/null 2>&1 || die "KWin is not running on the session bus. Run this from inside your Plasma session."

tray_items() { # add|remove
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        var id = '$WIDGET_ID', add = '$1' === 'add', done = 0;
        panels().forEach(function (p) {
            p.widgets('org.kde.plasma.systemtray').forEach(function (t) {
                t.currentConfigGroup = ['General'];
                ['extraItems', 'knownItems'].forEach(function (key) {
                    var items = String(t.readConfig(key, '')).split(',').filter(function (s) {
                        return s.length > 0 && s !== id;
                    });
                    if (add) items.push(id);
                    t.writeConfig(key, items);
                });
                t.reloadConfig();
                done++;
            });
        });
        print(done);" 2>/dev/null || echo 0
}

if [ "$uninstall" = 1 ]; then
    tools=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")/tools/claim-keys.sh
    if [ ! -f "$tools" ]; then
        tools=$(mktemp)
        trap 'rm -f "$tools"' EXIT
        curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/tools/claim-keys.sh" -o "$tools"
    fi
    bash "$tools" --release >/dev/null
    tray_items remove >/dev/null
    kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" false
    qdbus6 org.kde.KWin /KWin reconfigure
    kpackagetool6 --type KWin/Script --remove "$SCRIPT_ID" >/dev/null 2>&1 || true
    kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" >/dev/null 2>&1 || true
    say "MindTile removed. Plasma has its keys back. Saved layouts are left in ~/.config/mindtilerc."
    exit 0
fi

# Use the checkout this script sits in, or download the repository.
here=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")
if [ -z "$here" ] || [ ! -f "$here/package/metadata.json" ] || [ ! -f "$here/widget/metadata.json" ]; then
    command -v curl >/dev/null || die "curl not found"
    command -v tar >/dev/null || die "tar not found"
    here=$(mktemp -d)
    trap 'rm -rf "$here"' EXIT
    say "Downloading $REPO ($BRANCH)"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$here" --strip-components=1
fi

say "Installing the KWin script"
if kpackagetool6 --type KWin/Script --show "$SCRIPT_ID" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$here/package" >/dev/null
else
    kpackagetool6 --type KWin/Script --install "$here/package" >/dev/null
fi

loaded() {
    [ "$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded "$SCRIPT_ID" 2>/dev/null)" = true ]
}

wait_for() { # true|false
    for _ in $(seq 1 50); do
        if loaded; then [ "$1" = true ] && return 0; else [ "$1" = false ] && return 0; fi
        sleep 0.1
    done
    return 1
}

# Restart the script so an upgrade takes effect.
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" false
qdbus6 org.kde.KWin /KWin reconfigure
wait_for false || true
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
qdbus6 org.kde.KWin /KWin reconfigure
wait_for true || die "the KWin script did not start. Check: journalctl --user -b | grep -i mindtile"

say "Installing the panel widget"
if kpackagetool6 --type Plasma/Applet --show "$WIDGET_ID" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$here/widget" >/dev/null
else
    kpackagetool6 --type Plasma/Applet --install "$here/widget" >/dev/null
fi

if [ "$tray" = 1 ]; then
    if [ "$(tray_items add)" = 0 ]; then
        say "No system tray found. Add the MindTile widget to a panel by hand (Add Widgets...)."
    else
        say "Added the widget to the system tray"
    fi
fi

if [ "$claim_keys" = 1 ]; then
    bash "$here/tools/claim-keys.sh" >/dev/null
    say "MindTile now has Meta+T, Meta+R, Meta+Shift+F, Meta+arrows and Meta+Shift+arrows"
fi

say "Done. Every desktop starts in Floating; press Meta+T to switch."
say "If the widget shows an old version, run: plasmashell --replace &"
