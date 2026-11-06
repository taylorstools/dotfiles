import QtQuick
import QtQuick.Layouts
import qs.Common

// One button of a segmented tab bar (icon + label, filled when current).
// Meant to sit in a RowLayout; it fills its share of the row.
Rectangle {
    id: root

    property string icon
    property string text
    property bool current: false

    signal clicked

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: 8
    color: current ? Theme.primary : (mouse.containsMouse ? Theme.widgetHover : "transparent")

    Row {
        anchors.centerIn: parent
        // Material Symbols leave about 3px blank each side of an 18px glyph, so
        // the icon's blank edge counted towards the row and pushed what you see
        // right. Half of it back centres the visible icon and label.
        anchors.horizontalCenterOffset: root.icon !== "" ? -1.5 : 0
        spacing: 6

        // Text-only buttons (no icon) keep their label centred.
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            size: 18
            color: root.current ? Theme.onPrimary : Theme.surfaceVariantText
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.current ? Theme.onPrimary : Theme.surfaceVariantText
            font.pixelSize: 13
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
