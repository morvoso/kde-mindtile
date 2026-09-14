// MindTile panel widget. Shows the layout of the current virtual desktop and
// switches it by invoking the KWin script's global shortcuts over D-Bus.
// The KWin script saves each desktop's layout to ~/.config/mindtilerc, which
// is where the current state is read from.

import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property var layouts: [
        { mode: "floating", label: "Floating", icon: "floating", shortcut: "MindTile: Floating layout" },
        { mode: "dwindle", label: "Tiles", icon: "tiles", shortcut: "MindTile: Tiles layout" },
        { mode: "columns", label: "Columns", icon: "columns", shortcut: "MindTile: Columns layout" },
    ]
    property string mode: "floating"
    property bool scriptLoaded: true
    readonly property var current: layouts.find(l => l.mode === mode) || layouts[0]

    function iconUrl(name) {
        return Qt.resolvedUrl("../icons/" + name + ".svg");
    }

    Plasmoid.icon: iconUrl(current.icon)
    Plasmoid.title: "MindTile"
    toolTipMainText: "Window layout"
    toolTipSubText: scriptLoaded ? current.label : "The MindTile KWin script is not running"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    preferredRepresentation: compactRepresentation

    function refresh() {
        state.sync();
        let modes = {};
        try {
            modes = JSON.parse(state.value("modes", "{}"));
        } catch (e) {
            modes = {};
        }
        kwinrc.sync();
        const fallback = String(kwinrc.value("DefaultMode", "floating"));
        root.mode = modes[String(desktops.currentDesktop)] || fallback;
    }

    function checkScript() {
        const reply = DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/Scripting",
            iface: "org.kde.kwin.Scripting",
            member: "isScriptLoaded",
            arguments: [new DBus.string("mindtile")],
        });
        reply.finished.connect(() => {
            root.scriptLoaded = !reply.isError && reply.value === true;
        });
    }

    function switchTo(layout) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel",
            path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component",
            member: "invokeShortcut",
            arguments: [new DBus.string(layout.shortcut)],
        });
        root.mode = layout.mode;
        root.expanded = false;
        refreshSoon.restart();
    }

    function cycle() {
        const i = layouts.findIndex(l => l.mode === mode);
        switchTo(layouts[(i + 1) % layouts.length]);
    }

    TaskManager.VirtualDesktopInfo {
        id: desktops
        onCurrentDesktopChanged: root.refresh()
    }

    Settings {
        id: state
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/mindtilerc"
        category: "Layout"
    }

    Settings {
        id: kwinrc
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwinrc"
        category: "Script-mindtile"
    }

    // Meta+T changes the layout without telling the widget, so the saved
    // state is re-read once a second. QSettings only re-parses the file when
    // it has changed on disk.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoon
        interval: 300
        onTriggered: root.refresh()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkScript()
    }

    Component.onCompleted: refresh()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Floating"
            checkable: true
            checked: root.mode === "floating"
            onTriggered: root.switchTo(root.layouts[0])
        },
        PlasmaCore.Action {
            text: "Tiles"
            checkable: true
            checked: root.mode === "dwindle"
            onTriggered: root.switchTo(root.layouts[1])
        },
        PlasmaCore.Action {
            text: "Columns"
            checkable: true
            checked: root.mode === "columns"
            onTriggered: root.switchTo(root.layouts[2])
        }
    ]

    compactRepresentation: MouseArea {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.cycle();
            } else {
                root.expanded = !root.expanded;
            }
        }
        onWheel: wheel => {
            if (Math.abs(wheel.angleDelta.y) >= 120) {
                root.cycle();
            }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height, Kirigami.Units.iconSizes.medium)
            height: width
            source: root.iconUrl(root.current.icon)
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: root.scriptLoaded ? (parent.containsMouse ? 1 : 0.85) : 0.4
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: column.implicitHeight
        Layout.preferredHeight: column.implicitHeight
        collapseMarginsHint: true

        ColumnLayout {
            id: column
            anchors.fill: parent
            spacing: 0

            Repeater {
                model: root.layouts
                delegate: PlasmaComponents.ItemDelegate {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label
                    highlighted: root.mode === modelData.mode
                    enabled: root.scriptLoaded
                    onClicked: root.switchTo(modelData)

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing * 2

                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            source: root.iconUrl(modelData.icon)
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: modelData.label
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing * 2
                visible: !root.scriptLoaded
                text: "The MindTile KWin script is not running. Enable it in System Settings > Window Management > KWin Scripts."
                wrapMode: Text.Wrap
            }
        }
    }
}
