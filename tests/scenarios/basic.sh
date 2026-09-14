# Four windows through every layout and back to floating.
kwrite >/dev/null 2>&1 & sleep 2.5
konsole >/dev/null 2>&1 & sleep 2.5
kcalc >/dev/null 2>&1 & sleep 2.5
dolphin >/dev/null 2>&1 & sleep 3
dump floating; shot 1-floating
kg "MindTile: Tiles layout" 1.5; dump tiles; shot 2-tiles
kg "MindTile: Cycle size" 1; kg "MindTile: Move left" 1.5; dump tiles-sized-moved; shot 3-tiles-sized-moved
kg "MindTile: Columns layout" 1.5; dump columns; shot 4-columns
kg "MindTile: Focus left" 1; kg "MindTile: Focus left" 1; kg "MindTile: Focus left" 1.5; dump columns-scrolled; shot 5-columns-scrolled
kg "MindTile: Float window" 1.5; dump columns-one-floating; shot 6-columns-one-floating
kg "MindTile: Floating layout" 1.5; dump back-to-floating; shot 7-floating-again
