import QtQuick
import qs.Common

// Border lines on chosen sides of a panel. An attached panel (one sitting
// against the taskbar and the screen edge) only gets a border on the sides
// facing the desktop, which Rectangle.border can't do.
Item {
    id: root

    property bool topEdge: false
    property bool bottomEdge: false
    property bool leftEdge: false
    property bool rightEdge: false
    property color color: Theme.blurBorder

    anchors.fill: parent
    z: 100

    Rectangle {
        visible: root.topEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: root.color
    }

    Rectangle {
        visible: root.bottomEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: root.color
    }

    Rectangle {
        visible: root.leftEdge
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 1
        color: root.color
    }

    Rectangle {
        visible: root.rightEdge
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: root.color
    }
}
