import QtQuick
import qs.Common

// Flat button with a Material Symbols icon and an optional label.
Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property real iconSize: 20
    property real iconRotation: 0
    property color contentColor: Theme.surfaceText
    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitHeight: 32
    implicitWidth: text !== "" ? row.implicitWidth + Theme.spacingS * 2 : implicitHeight
    radius: Theme.cornerRadius / 2
    color: hovered ? Theme.widgetHover : "transparent"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingS

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: root.iconSize
            rotation: root.iconRotation
            color: root.contentColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.contentColor
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
