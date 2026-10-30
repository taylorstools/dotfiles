import QtQuick
import qs.Common

// Text that turns into a button on hover, like the action buttons on
// notification pop-ups. The hover fill is Theme.widgetHover, so it still
// shows with the overlay opacity turned down.
Rectangle {
    id: root

    property alias text: label.text
    readonly property bool hovered: mouse.containsMouse

    signal clicked

    implicitWidth: label.implicitWidth + 20
    implicitHeight: 28
    radius: 8
    color: hovered ? Theme.widgetHover : "transparent"

    StyledText {
        id: label
        anchors.centerIn: parent
        font.pixelSize: 12
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
