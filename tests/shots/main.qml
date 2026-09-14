// Screenshot helper: "Shots: place" puts each app window at a fixed spot
// so the Floating screenshot looks like a desktop someone arranged.
import QtQuick
import org.kde.kwin

Item {
    readonly property var spots: ({
        "org.kde.dolphin": [70, 60, 1000, 640],
        "org.kde.kwrite": [880, 120, 900, 700],
        "org.kde.konsole": [260, 470, 860, 480],
        "org.kde.kcalc": [1450, 560, 380, 420],
    })
    ShortcutHandler {
        name: "Shots: place"
        text: "Shots: place windows"
        sequence: ""
        onActivated: {
            var ws = Workspace.stackingOrder;
            for (var i = 0; i < ws.length; i++) {
                var s = spots[ws[i].resourceClass];
                if (s) {
                    ws[i].frameGeometry = Qt.rect(s[0], s[1], s[2], s[3]);
                }
            }
        }
    }
}
