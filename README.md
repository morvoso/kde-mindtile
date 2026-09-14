# kde-mindtile

KWin script and panel widget for KDE Plasma 6 that adds three window layouts,
set per virtual desktop:

- Floating: normal KWin behaviour, plus half-screen snapping and size presets.
- Tiles: dwindle tiling. Each new window splits the focused tile along its longer side.
- Columns: scrolling columns. Full-height columns on a strip that scrolls to the focused window.

When a window gets tiled, its floating geometry is saved. Switching the desktop
back to Floating, or floating that one window, puts it back at the same size
and position. A window that was maximized before it was tiled gets its
pre-maximize geometry back.

## Requirements

- KDE Plasma 6 (tested on Plasma 6.7.5, Wayland)
- `kpackagetool6`, `kwriteconfig6`, `qdbus6`, `gdbus` (installed with Plasma)
- `curl` and `tar` for the one-line install

## Install

Run this from inside your Plasma session as your normal user. Don't use sudo.

```sh
curl -fsSL https://raw.githubusercontent.com/morvoso/kde-mindtile/main/install.sh | bash
```

Options go after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/morvoso/kde-mindtile/main/install.sh | bash -s -- --no-keys
```

| Option        | Effect |
|---------------|--------|
| `--no-keys`   | Don't take over Plasma's default shortcuts (see Shortcuts below) |
| `--no-tray`   | Install the widget but don't add it to the system tray |
| `--uninstall` | Remove everything and give Plasma its shortcuts back |

From a clone:

```sh
git clone https://github.com/morvoso/kde-mindtile.git
cd kde-mindtile
./install.sh
```

Running the installer again upgrades an existing install.

### What the installer changes

- Installs the KWin script to `~/.local/share/kwin/scripts/mindtile`
- Installs the widget to `~/.local/share/plasma/plasmoids/com.github.morvoso.mindtile`
- Sets `mindtileEnabled=true` under `[Plugins]` in `~/.config/kwinrc` and tells KWin to reload
- Adds `com.github.morvoso.mindtile` to the system tray's `extraItems` and `knownItems`
- Unless `--no-keys` is given, unbinds these Plasma shortcuts and gives the keys to MindTile:
  - `Meta+T` (Toggle Tiles Editor)
  - `Meta+Left/Right/Up/Down` (Quick Tile Window)
  - `Meta+Shift+Left/Right` (Window to Previous/Next Screen)

The layout of each desktop is saved in `~/.config/mindtilerc`.

If the tray still shows an older version of the widget after an upgrade,
restart plasmashell:

```sh
plasmashell --replace & disown
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/morvoso/kde-mindtile/main/install.sh | bash -s -- --uninstall
```

or `./install.sh --uninstall` from a clone. This restores Plasma's default
bindings for the keys listed above, removes the widget from the tray, disables
and removes the script, and removes the widget. `~/.config/mindtilerc` is left
in place.

## Shortcuts

| Key | Floating | Tiles | Columns |
|-----|----------|-------|---------|
| `Meta+T` | Next layout | Next layout | Next layout |
| `Meta+arrows` | Focus the window in that direction | same | same |
| `Meta+Shift+Left/Right` | Snap to the left/right half, press again to release | Swap with the neighbouring tile | Move the column left/right |
| `Meta+Shift+Up` | Maximize | Swap with the tile above | nothing |
| `Meta+Shift+Down` | Unmaximize or release a snap | Swap with the tile below | nothing |
| `Meta+R` | Resize to 50%, 70%, 90% of the screen around the window's centre | Split share: 1/3, 1/2, 2/3 | Column width: 1/3, 1/2, 2/3, full |
| `Meta+Shift+F` | nothing | Float or re-tile the focused window | same |

A floated window in Tiles or Columns uses the Floating column for
`Meta+Shift+arrows` and `Meta+R`.

These have no key by default and can be bound in System Settings > Keyboard >
Shortcuts > KWin:

- MindTile: Floating layout / Tiles layout / Columns layout
- MindTile: Focus the next / previous window in the layout

If you installed with `--no-keys`, the default keys above still belong to
Plasma. Either rebind them yourself, or run `tools/claim-keys.sh` from a clone.
`tools/claim-keys.sh --release` reverses it.

## Mouse

- Dragging a tile onto another tile swaps them.
- Dragging a tile to another monitor moves it into that monitor's layout.
- Resizing a tile's edge moves the split that edge belongs to. In Columns it sets the column width.

## Widget

The widget shows the layout icon for the current desktop.

- Left click or scrolling moves to the next layout.
- Middle click opens a list of the three layouts.
- Right click shows the layouts as menu entries.
- The icon is dimmed when the KWin script isn't running.

It reads `~/.config/mindtilerc` for the current layout and switches layouts by
invoking the script's shortcuts through kglobalaccel over D-Bus.

## Settings

System Settings > Window Management > KWin Scripts > MindTile > Configure:

- Gap between tiles (default 8 px)
- Gap at the screen edge (default 8 px)
- Layout for desktops that haven't been set yet (default floating)
- Scroll animation for Columns
- Apps that always float: comma-separated window classes. A trailing `*`
  matches a prefix, e.g. `steam_app_*`

Dialogs, transient windows, windows on all desktops and windows that can't be
resized always float.

## Known limitations

- KWin scripts can't clip a window to one monitor. In Columns, a column that
  scrolls off its monitor onto a neighbouring one is moved below the visible
  desktop until it scrolls back.
- Tiles keep their normal title bars. Apps aren't told they are tiled, so GTK
  windows keep rounded corners and shadows.
- Saved floating geometry is stored in `~/.config/mindtilerc` against KWin's
  internal window ids. It survives the script being reloaded (for example
  when you apply its settings), but not a KWin restart or logging out. The
  per-desktop layout is always kept.
- A window with a minimum size larger than its tile will overflow the tile.

## Development

```
package/                  KWin script (declarative QML)
  contents/ui/engine.js   layout engine, no QML dependencies
  contents/ui/main.qml    connects the engine to the KWin Workspace API
widget/                   Plasma applet
tools/claim-keys.sh       moves the default keys between Plasma and MindTile
tests/                    unit tests and headless KWin scenarios
```

```sh
make test            # node --test tests/
make session         # runs the script in kwin_wayland --virtual, screenshots in build/session
make session-multi   # same with two outputs
make install         # ./install.sh from the checkout
make dist            # build/mindtile.kwinscript for "Install from File"
```

The headless sessions set `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`
and `XDG_STATE_HOME` to `build/session`. Without that, a nested KWin writes to
your real `kwinrc`, `kwinoutputconfig.json` and `kglobalshortcutsrc`.

## License

MIT. See [LICENSE](LICENSE). You can use, modify and redistribute this, but
copies and derived work have to keep the copyright notice crediting
Justin Bryson.
