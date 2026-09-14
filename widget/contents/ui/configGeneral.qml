// Settings page: the gaps between and around tiles, and the border drawn
// around the focused window. Saved in the widget's config, then copied to
// ~/.config/mindtilerc for the KWin script (see main.qml).

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property alias cfg_gap: gap.value
    property alias cfg_outerGap: outerGap.value
    property alias cfg_border: border.checked
    property alias cfg_borderWidth: borderWidth.value
    property alias cfg_useAccentColor: useAccent.checked
    property alias cfg_borderColor: borderColor.color

    property int cfg_gapDefault
    property int cfg_outerGapDefault
    property bool cfg_borderDefault
    property int cfg_borderWidthDefault
    property bool cfg_useAccentColorDefault
    property color cfg_borderColorDefault

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: "Gap between tiles:"

            QQC2.SpinBox {
                id: gap
                editable: true
                from: 0
                to: 64
            }

            QQC2.Label {
                text: "px"
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Gap at the screen edge:"

            QQC2.SpinBox {
                id: outerGap
                editable: true
                from: 0
                to: 64
            }

            QQC2.Label {
                text: "px"
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: border
            Kirigami.FormData.label: "Focused window:"
            text: "Draw a border around it"
        }

        RowLayout {
            Kirigami.FormData.label: "Border width:"
            enabled: border.checked

            QQC2.SpinBox {
                id: borderWidth
                editable: true
                from: 1
                to: 16
            }

            QQC2.Label {
                text: "px"
            }
        }

        QQC2.CheckBox {
            id: useAccent
            Kirigami.FormData.label: "Border color:"
            enabled: border.checked
            text: "Use the accent color"
        }

        KQuickControls.ColorButton {
            id: borderColor
            enabled: border.checked && !useAccent.checked
            showAlphaChannel: false
            dialogTitle: "Border color"
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            text: "Borders sit in the gap, so a border wider than the gap between tiles overlaps the next window."
            wrapMode: Text.Wrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
