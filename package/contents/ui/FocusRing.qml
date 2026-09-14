// The border around the focused window: a click-through on-screen-display
// window drawn just outside the window's frame, in the gap between tiles.

import QtQuick
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: ring

    property color borderColor: "#3daee9"
    property int borderWidth: 3
    property int radius: 6

    /// Wrap `rect` (a window's frame geometry), or hide with null.
    function wrap(rect) {
        if (!rect || borderWidth <= 0) {
            visible = false;
            return;
        }
        var b = borderWidth;
        frame.width = Math.round(rect.width + 2 * b);
        frame.height = Math.round(rect.height + 2 * b);
        x = Math.round(rect.x - b);
        y = Math.round(rect.y - b);
        visible = true;
    }

    type: PlasmaCore.Dialog.OnScreenDisplay
    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Types.NoBackground
    outputOnly: true
    visible: false

    mainItem: Rectangle {
        id: frame
        width: 100
        height: 100
        color: "transparent"
        radius: ring.radius + ring.borderWidth
        border.color: ring.borderColor
        border.width: ring.borderWidth
    }
}
