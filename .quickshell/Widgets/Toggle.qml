import QtQuick
import qs.Common

// On/off switch. It doesn't flip itself: handle `toggled` and update `checked`.
Rectangle {
    id: root

    property bool checked: false

    signal toggled

    implicitWidth: 36
    implicitHeight: 20
    radius: height / 2
    color: checked ? Theme.primary : Theme.surfaceContainerHighest
    border.width: checked ? 0 : 1
    border.color: Theme.outline

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3
        width: 14
        height: 14
        radius: 7
        color: root.checked ? Theme.onPrimary : Theme.outline

        Behavior on x {
            NumberAnimation {
                duration: Theme.animShort
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
