# Columns with the focus border and Meta+wheel: the border follows the
# focused window and lets clicks through, the wheel walks the strip.
echo "== effect loaded: $(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded mindtile_wheel)" >&2
kwrite >/dev/null 2>&1 & sleep 2.5
konsole >/dev/null 2>&1 & sleep 2.5
kcalc >/dev/null 2>&1 & sleep 2.5
dolphin >/dev/null 2>&1 & sleep 3
kg "MindTile: Columns layout" 1.5; dump columns; shot focus-1-columns
mti move 960 540 press 125 wheel -1 release 125 sleep 700
dump wheel-up-once; shot focus-2-wheel-up
mti press 125 wheel -1 sleep 400 wheel -1 release 125 sleep 700
dump wheel-up-twice-more
mti press 125 wheel -1 release 125 sleep 700
dump wheel-up-at-the-start
mti press 125 wheel 1 release 125 sleep 700
dump wheel-down
mti move 1500 540 click left sleep 700
dump clicked-right-column; shot focus-3-clicked
