// Test helper: prints every application window's geometry when its shortcut
// is invoked, so the session test can check what MindTile did.
import QtQuick
import org.kde.kwin

Item {
    ShortcutHandler {
        name: "Probe: dump"
        text: "Probe: dump window geometry"
        sequence: ""
        onActivated: {
            var ws = Workspace.stackingOrder;
            var out = [];
            for (var i = 0; i < ws.length; i++) {
                var w = ws[i];
                if (!w.normalWindow) continue;
                var g = w.frameGeometry;
                out.push({ cls: w.resourceClass, caption: w.caption, x: g.x, y: g.y, w: g.width, h: g.height,
                           active: w === Workspace.activeWindow, max: w.maximizeMode });
            }
            console.warn("PROBE " + JSON.stringify(out) + " cursor=" + Workspace.cursorPos.x + "," + Workspace.cursorPos.y);
        }
    }
    Connections {
        target: Workspace
        function onWindowAdded(w) {
            w.interactiveMoveResizeStarted.connect(function () { console.warn("PROBE drag move=" + w.move + " resize=" + w.resize); });
        }
    }
}
