# Two screens: floating -> Tiles -> Columns (scrolled) -> Floating must put
# every window back where it was.
kwrite >/dev/null 2>&1 & sleep 2.5
konsole >/dev/null 2>&1 & sleep 2.5
kcalc >/dev/null 2>&1 & sleep 2.5
dolphin >/dev/null 2>&1 & sleep 3
dump floating; shot 1-floating
kg "MindTile: Next layout" 1.5; dump tiles
kg "MindTile: Next layout" 1.5; dump columns
kg "MindTile: Focus left" 0.6; kg "MindTile: Focus left" 0.6; kg "MindTile: Focus left" 1.5; dump columns-scrolled; shot 2-columns
kg "MindTile: Next layout" 1.5; dump floating-again; shot 3-floating-again
