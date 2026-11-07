import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The right-click menu, floating above the taskbar or beside the dock, opened
// through Popouts. Not a PopupWindow: niri's blur and WallpaperBackdrop both
// need a layer-shell window, so a popup's colour came out different from the
// bar's. This covers the whole screen, bar included, so a click anywhere else
// closes the menu.
Scope {
    id: root

    readonly property bool shown: Popouts.contextMenuScreen !== null

    onShownChanged: {
        if (shown)
            window.screen = Popouts.contextMenuScreen;
    }

    // Keeps the window up until the closing animation is done.
    PanelMotion {
        id: motion
        shown: root.shown
    }

    PanelWindow {
        id: window

        visible: motion.mapped
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "qstest:contextmenu"
        // Above the bar, which is on the Top layer.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                applyBlur();
        }

        Item {
            Region {
                id: blurRegion
                x: panel.x
                y: panel.y
                width: panel.width
                height: panel.height
            }
        }

        Connections {
            target: Settings
            function onBlurChanged() {
                window.applyBlur();
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Settings.blur && !Wallpaper.xrayBackdrop ? blurRegion : null;
        }

        Shortcut {
            sequences: ["Escape"]
            enabled: root.shown
            onActivated: Popouts.closeContextMenu()
        }

        // A click outside the menu, with any button, closes it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: Popouts.closeContextMenu()
        }

        Rectangle {
            id: panel

            readonly property real pad: Theme.spacingXS

            readonly property real wantedX: {
                switch (Popouts.contextMenuSide) {
                case "left":
                    return Popouts.contextMenuX - width;
                case "right":
                    return Popouts.contextMenuX;
                default:
                    return Popouts.contextMenuX - width / 2;
                }
            }
            readonly property real wantedY: Popouts.contextMenuSide === "top" ? Popouts.contextMenuY - height : Popouts.contextMenuY - height / 2

            // Kept on screen and clear of the taskbar, with the same gap it
            // floats above the taskbar with.
            x: Theme.snap(Math.max(Theme.spacingS, Math.min(wantedX, window.width - width - Theme.spacingS)))
            y: Theme.snap(Math.max(Theme.spacingS, Math.min(wantedY, window.height - Theme.barThickness - height - Theme.spacingS)))
            width: rows.width + pad * 2
            height: rows.height + pad * 2
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Fades and grows like the centred panels.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress
            // No second click while it fades out: pinning would undo itself.
            enabled: root.shown

            // X-ray: the blurred wallpaper under the panel's colour.
            WallpaperBackdrop {
                window: window
                onActiveChanged: window.applyBlur()
            }

            // Swallows clicks so they don't close the menu.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Column {
                id: rows

                x: panel.pad
                y: panel.pad
                // As wide as the longest row, so every row's hover fills it.
                width: Theme.snap(Math.max(0, ...Array.from(children).map(c => c.implicitWidth ?? 0)))

                Repeater {
                    model: Popouts.contextMenuItems

                    delegate: MenuRow {
                        required property var modelData
                        required property int index

                        width: rows.width
                        icon: modelData.icon ?? ""
                        text: modelData.text
                        // A row with no action is a label, like the dock's app name.
                        isLabel: !modelData.action
                        onClicked: {
                            Popouts.contextMenuItems[index].action();
                            Popouts.closeContextMenu();
                        }
                    }
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: menuRow

        property string icon
        property string text
        property bool isLabel: false

        signal clicked

        implicitWidth: line.implicitWidth + Theme.spacingS * 2
        height: isLabel ? 24 : 32
        radius: Theme.cornerRadius - Theme.spacingXS
        color: rowArea.containsMouse ? Theme.widgetHover : "transparent"

        Row {
            id: line

            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: menuRow.icon !== ""
                name: menuRow.icon
                size: 16
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: menuRow.text
                color: menuRow.isLabel ? Theme.outline : Theme.widgetText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            enabled: !menuRow.isLabel
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRow.clicked()
        }
    }
}
