import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Hover tooltip beside an item: above it by default (below it when there's
// no room, e.g. a title bar at the top of the screen), or to its left or
// right (`side`, for the dock).
//   Tooltip { target: someItem; text: "..."; shown: hovered }
// It lets the pointer through, so it can never take the hover from its own
// target (which made tooltips flicker when they ended up over it).
//
// When the target sits in a layer-shell window (the bar, dock, flyouts) the
// tooltip is a small layer-shell window of its own, placed on the screen
// over the target: a PopupWindow gets neither niri's blur nor
// WallpaperBackdrop, so it didn't follow the blur settings. In a normal
// window (the settings window), whose place on screen the shell can't know,
// it falls back to a BarPopup.
Item {
    id: root

    required property Item target
    property string text: ""
    property bool shown: false
    // Where the tooltip goes: "top" (flips below when there's no room),
    // "left" or "right".
    property string side: "top"
    property real gap: Theme.spacingXS

    readonly property bool active: shown && text !== "" && target !== null
    readonly property var targetWindow: target ? target.QsWindow.window : null
    readonly property bool layerShell: targetWindow !== null && targetWindow.anchors !== undefined && targetWindow.margins !== undefined

    LazyLoader {
        active: root.active && root.layerShell

        PanelWindow {
            id: tipWindow

            readonly property var host: root.targetWindow
            readonly property real screenWidth: screen?.width ?? 0
            readonly property real screenHeight: screen?.height ?? 0

            // Where the host window sits on its screen, from its anchors, as
            // WallpaperBackdrop works it out.
            readonly property real hostX: {
                if (host.anchors.right)
                    return screenWidth - host.margins.right - host.width;
                if (host.anchors.left)
                    return host.margins.left;
                return (screenWidth - host.width) / 2;
            }
            readonly property real hostY: {
                if (host.anchors.top)
                    return host.margins.top;
                if (host.anchors.bottom) {
                    const bar = host.exclusionMode === ExclusionMode.Normal ? Theme.barThickness : 0;
                    return screenHeight - host.margins.bottom - host.height - bar;
                }
                return (screenHeight - host.height) / 2;
            }

            // The target on screen. Read when the tooltip opens and when the
            // target resizes (tooltips are short-lived; nothing else moves
            // under the pointer while one shows).
            readonly property point targetPos: {
                root.target.width;
                root.target.height;
                return root.target.mapToItem(null, 0, 0);
            }
            readonly property real targetX: hostX + targetPos.x
            readonly property real targetY: hostY + targetPos.y

            readonly property real edge: Theme.spacingS
            readonly property real wantedX: {
                switch (root.side) {
                case "left":
                    return targetX - root.gap - width;
                case "right":
                    return targetX + root.target.width + root.gap;
                default:
                    return targetX + (root.target.width - width) / 2;
                }
            }
            readonly property real wantedY: {
                if (root.side !== "top")
                    return targetY + (root.target.height - height) / 2;
                const above = targetY - root.gap - height;
                return above >= edge ? above : targetY + root.target.height + root.gap;
            }

            screen: host.screen
            anchors {
                top: true
                left: true
            }
            // Margins count from the screen's edges, not the bar's or dock's
            // exclusive zones.
            exclusionMode: ExclusionMode.Ignore
            margins {
                left: Theme.snap(Math.max(edge, Math.min(wantedX, screenWidth - width - edge)))
                top: Theme.snap(Math.max(edge, Math.min(wantedY, screenHeight - height - edge)))
            }
            implicitWidth: Theme.snap(label.implicitWidth + Theme.spacingS * 2)
            implicitHeight: Theme.snap(label.implicitHeight + Theme.spacingS * 2)
            color: "transparent"
            mask: Region {}

            WlrLayershell.namespace: "qstest:tooltip"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                Region {
                    id: blurRegion
                    width: panel.width
                    height: panel.height
                }
            }

            Connections {
                target: Settings
                function onBlurChanged() {
                    tipWindow.applyBlur();
                }
            }

            Component.onCompleted: applyBlur()
            onVisibleChanged: applyBlur()

            function applyBlur() {
                // Region.radius only exists in newer Quickshell builds.
                if ("radius" in blurRegion)
                    blurRegion.radius = panel.radius;
                if (tipWindow.BackgroundEffect !== undefined)
                    tipWindow.BackgroundEffect.blurRegion = Settings.blur && !Wallpaper.xrayBackdrop ? blurRegion : null;
            }

            Rectangle {
                id: panel

                anchors.fill: parent
                radius: Theme.cornerRadius / 2
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.blurBorder

                // X-ray: the blurred wallpaper under the panel's colour.
                WallpaperBackdrop {
                    window: tipWindow
                    onActiveChanged: tipWindow.applyBlur()
                }

                StyledText {
                    id: label
                    x: Theme.spacingS
                    y: Theme.spacingS
                    text: root.text
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    // A normal window: no blur either way, just a popup.
    LazyLoader {
        active: root.active && !root.layerShell

        BarPopup {
            target: root.target
            gap: root.gap
            padding: Theme.spacingS
            radius: Theme.cornerRadius / 2
            visible: true
            mask: Region {}

            StyledText {
                text: root.text
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
