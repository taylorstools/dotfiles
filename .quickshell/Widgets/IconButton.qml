import QtQuick
import qs.Common

// Flat button with a Material Symbols icon and an optional label.
Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property real iconSize: 20
    property real iconRotation: 0
    property bool filled: false
    property color contentColor: Theme.surfaceText
    property color restColor: "transparent"
    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitHeight: 32
    implicitWidth: text !== "" ? row.implicitWidth + (icon !== "" ? Theme.spacingS : Theme.spacingM) * 2 : implicitHeight
    radius: Theme.cornerRadius / 2
    color: hovered ? Theme.widgetHover : restColor

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingS

        // Text-only buttons keep their label centred.
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            size: root.iconSize
            rotation: root.iconRotation
            filled: root.filled
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
