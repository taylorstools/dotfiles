import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Thumbnail grid of the wallpaper folder; click one to set it. Used by the
// clock flyout's Wallpapers tab and the settings window's Wallpaper page.
GridView {
    id: root

    property int columns: 3

    clip: true
    cellWidth: Math.floor(width / columns)
    cellHeight: Math.round(cellWidth * 9 / 16)
    boundsBehavior: Flickable.StopAtBounds
    model: Wallpaper.images

    delegate: Item {
        id: thumb

        required property string modelData
        readonly property bool current: Wallpaper.path === modelData

        width: root.cellWidth
        height: root.cellHeight

        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Theme.cornerRadius / 1.5
            color: Theme.surfaceContainerHigh
            border.width: thumb.current ? 3 : 0
            border.color: Theme.primary

            Image {
                anchors.fill: parent
                source: "file://" + thumb.modelData
                // Decoded once at this size and cached for the session.
                sourceSize.width: 320
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: thumbMouse.containsMouse || thumb.current ? 1 : 0.85
            }
        }

        MouseArea {
            id: thumbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Wallpaper.set(thumb.modelData)
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.count === 0
        text: "No images in the wallpaper folder"
        color: Theme.surfaceVariantText
    }
}
