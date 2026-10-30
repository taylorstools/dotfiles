import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// One notification, used by the clock flyout's tray and by the corner
// pop-ups. The tray version has an "app · 5 min ago" line and a larger image;
// the pop-up is compact. Clicking the card runs the default action; the
// other actions are text buttons along the bottom.
Rectangle {
    id: root

    required property var notification
    property bool popup: false
    readonly property bool hovered: cardMouse.containsMouse || closeButton.hovered

    readonly property var buttons: Array.from(notification?.actions ?? []).filter(a => a.identifier !== "default" && a.text !== "")
    // Quickshell hands `notify-send -i <name>` over as image://icon/<name> and
    // image files as image://icon//path. A bare icon name is the app's icon,
    // not a picture to show large.
    readonly property string imageSource: notification?.image ?? ""
    readonly property bool imageIsIcon: imageSource.startsWith("image://icon/") && !imageSource.startsWith("image://icon//")
    readonly property string iconSource: {
        const n = notification;
        if (!n)
            return "";
        return Apps.resolveIcon(n.appIcon) || (imageIsIcon ? imageSource : "") || (n.desktopEntry ? Apps.iconFor(n.desktopEntry) : "");
    }

    implicitHeight: content.implicitHeight + 20
    radius: 10
    color: popup ? Theme.popupBackground : Theme.surfaceContainerHigh
    border.width: popup ? 1 : 0
    border.color: Theme.blurBorder

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: !root.popup
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifications.activate(root.notification)
    }

    RowLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 8
            color: Theme.surfaceContainerHighest

            IconImage {
                id: appIcon
                anchors.centerIn: parent
                implicitSize: 20
                source: root.iconSource
                visible: status === Image.Ready
                asynchronous: true
            }

            StyledText {
                anchors.centerIn: parent
                visible: !appIcon.visible
                text: (root.notification?.appName || "?").charAt(0).toUpperCase()
                color: Theme.primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.popup
                    text: (root.notification?.appName || "Notification") + " · " + Notifications.ago(root.notification, clock.date)
                    color: Theme.outline
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.popup
                    text: root.notification?.summary ?? ""
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                IconButton {
                    id: closeButton
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: 20
                    icon: "close"
                    iconSize: 15
                    contentColor: Theme.surfaceVariantText
                    onClicked: root.notification.dismiss()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.popup && text !== ""
                text: root.notification?.summary ?? ""
                font.pixelSize: 13
                font.weight: Font.Medium
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.notification?.body ?? ""
                textFormat: Text.PlainText
                color: Theme.surfaceVariantText
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: root.popup ? 2 : 4
                elide: Text.ElideRight
            }

            ClippingRectangle {
                Layout.topMargin: 4
                Layout.preferredWidth: root.popup ? 96 : parent.width
                Layout.preferredHeight: root.popup ? 54 : 110
                visible: root.imageSource !== "" && !root.imageIsIcon && image.status !== Image.Error
                radius: 6
                color: Theme.surfaceContainerHighest

                Image {
                    id: image
                    anchors.fill: parent
                    source: root.imageIsIcon ? "" : root.imageSource
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 480
                    asynchronous: true
                }
            }

            // Text buttons that only show a background on hover.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.leftMargin: -10
                visible: root.buttons.length > 0
                spacing: 2

                Repeater {
                    model: root.buttons

                    delegate: Rectangle {
                        id: actionButton

                        required property var modelData

                        width: actionText.implicitWidth + 20
                        height: 28
                        radius: 8
                        color: actionMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                        StyledText {
                            id: actionText
                            anchors.centerIn: parent
                            text: actionButton.modelData.text
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: actionButton.modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
