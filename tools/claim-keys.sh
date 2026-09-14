#!/bin/bash
# Gives MindTile the MindOS keys that Plasma binds to its own actions by
# default (Meta+T, Meta+arrows, Meta+Shift+Left/Right), or gives them back.
#
#   tools/claim-keys.sh            take the keys for MindTile
#   tools/claim-keys.sh --release  restore Plasma's bindings, unbind MindTile's
#
# It talks to kglobalaccel, so the change is live and saved like any change
# made in System Settings > Shortcuts. MindTile must be enabled first.
set -euo pipefail

META=$((0x10000000)); SHIFT=$((0x02000000))
LEFT=$((0x01000012)); UP=$((0x01000013)); RIGHT=$((0x01000014)); DOWN=$((0x01000015))
T=$((0x54)); R=$((0x52)); F=$((0x46))

set_keys() { # component action friendly-action key|none
    local keys="@a(ai) []"
    [ "$4" != none ] && keys="[([$4],)]"
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.setForeignShortcutKeys \
        "[\"$1\", \"$2\", \"KWin\", \"$3\"]" "$keys" >/dev/null
}

# Plasma action, its description, the key it has by default.
plasma=(
    "Edit Tiles|Toggle Tiles Editor|$((META | T))"
    "Window Quick Tile Left|Quick Tile Window to the Left|$((META | LEFT))"
    "Window Quick Tile Right|Quick Tile Window to the Right|$((META | RIGHT))"
    "Window Quick Tile Top|Quick Tile Window to the Top|$((META | UP))"
    "Window Quick Tile Bottom|Quick Tile Window to the Bottom|$((META | DOWN))"
    "Window to Previous Screen|Move Window to Previous Screen|$((META | SHIFT | LEFT))"
    "Window to Next Screen|Move Window to Next Screen|$((META | SHIFT | RIGHT))"
)
mindtile=(
    "MindTile: Next layout|MindTile: Next layout (Floating, Tiles, Columns)|$((META | T))"
    "MindTile: Cycle size|MindTile: Step the focused window's size|$((META | R))"
    "MindTile: Float window|MindTile: Float or tile the focused window|$((META | SHIFT | F))"
    "MindTile: Focus left|MindTile: Focus the window to the left|$((META | LEFT))"
    "MindTile: Focus right|MindTile: Focus the window to the right|$((META | RIGHT))"
    "MindTile: Focus up|MindTile: Focus the window above|$((META | UP))"
    "MindTile: Focus down|MindTile: Focus the window below|$((META | DOWN))"
    "MindTile: Move left|MindTile: Move the window left|$((META | SHIFT | LEFT))"
    "MindTile: Move right|MindTile: Move the window right|$((META | SHIFT | RIGHT))"
    "MindTile: Move up|MindTile: Move the window up|$((META | SHIFT | UP))"
    "MindTile: Move down|MindTile: Move the window down|$((META | SHIFT | DOWN))"
)

if [ "${1:-}" = --release ]; then
    for entry in "${mindtile[@]}"; do IFS='|' read -r name text key <<<"$entry"; set_keys kwin "$name" "$text" none; done
    for entry in "${plasma[@]}"; do IFS='|' read -r name text key <<<"$entry"; set_keys kwin "$name" "$text" "$key"; done
    echo "Plasma has its keys back; MindTile's shortcuts are unbound."
else
    if ! qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames | grep -q "^MindTile: Next layout$"; then
        echo "MindTile is not running: enable it in System Settings > Window Management > KWin Scripts first." >&2
        exit 1
    fi
    for entry in "${plasma[@]}"; do IFS='|' read -r name text key <<<"$entry"; set_keys kwin "$name" "$text" none; done
    for entry in "${mindtile[@]}"; do IFS='|' read -r name text key <<<"$entry"; set_keys kwin "$name" "$text" "$key"; done
    echo "MindTile has the MindOS keys. Undo with: $0 --release"
fi
