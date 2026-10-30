import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Battery glyph + percentage (Services/BatteryInfo).
// Click for the battery flyout. Hidden on machines without a battery (the
// HTPCs).
Item {
    id: root

    property real barThickness: Theme.barThickness
    property var parentScreen: null

    readonly property bool present: BatteryInfo.present
    readonly property real level: BatteryInfo.level
    readonly property bool charging: BatteryInfo.charging
    readonly property string icon: BatteryInfo.icon

    visible: present
    implicitWidth: present ? row.implicitWidth + Theme.widgetPadding * 2 : 0
    implicitHeight: barThickness

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse || (Popouts.batteryScreen !== null && Popouts.batteryScreen === root.parentScreen) ? Theme.widgetHover : "transparent"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Popouts.toggleBattery(root.parentScreen)
    }

    Row {
        id: row
        anchors.centerIn: parent
        // 1 apart (plus 2 physical px, measured), and
        // the -4 icon offset.
        spacing: 1 + 2 / Theme.dpr

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: Theme.barIconSize(root.barThickness, false, -4)
            color: root.level < 10 && !root.charging ? Theme.error : Theme.widgetText
        }

        // Tabular digits, at least as wide as "00%",
        // so the widget doesn't change width as the level changes.
        StyledText {
            id: percent
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(implicitWidth, reserve.implicitWidth))
            horizontalAlignment: Text.AlignHCenter
            text: root.level + "%"
            font.pixelSize: Theme.barTextSize(root.barThickness)
            font.features: ({
                    "tnum": 1
                })

            // A hidden copy measures "00%" with the same font features.
            StyledText {
                id: reserve
                visible: false
                text: (root.level + "%").replace(/\d/g, "0")
                font: percent.font
            }
        }
    }
}
