import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The collapsed tray's icons, above the bar's chevron. It opens and closes
// like the other bar flyouts: opening it closes them, and a click on another
// flyout's button, elsewhere on the bar or anywhere outside, or Esc, closes
// it. Left-clicking an icon activates it and closes the flyout; right-click
// menus open from here.
Scope {
    id: root

    readonly property bool shown: Popouts.trayScreen !== null
    readonly property var items: SystemTray.items.values
    readonly property real iconSize: Theme.barIconSize(Theme.barThickness, false)

    function close() {
        Popouts.trayScreen = null;
    }

    onShownChanged: {
        if (shown)
            window.screen = Popouts.trayScreen;
    }

    // Nothing left to show (the last tray app quit): close.
    onItemsChanged: {
        if (items.length === 0)
            close();
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
        // Covers the screen above the bar, so clicks on the bar still reach it.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"

        WlrLayershell.namespace: "qstest:tray"
        WlrLayershell.layer: WlrLayer.Top
        // Exclusive, like the other bar flyouts: on-demand focus lets a press
        // on the bar take the keyboard mid-click, and Qt cancels that click.
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                applyBlur();
        }

        Item {
            // Follows the panel as it rises out of the bar. Kept inside the
            // window: attached, the panel reaches past its bottom.
            Region {
                id: blurRegion
                x: panel.x
                y: panel.y + (1 - motion.progress) * 16
                width: panel.width
                height: panel.height

                Region {
                    intersection: Intersection.Intersect
                    width: window.width
                    height: window.height
                }
            }
        }

        // Re-apply when blur is switched in the settings window, or the panel
        // changes shape (attached or not, corner radius).
        Connections {
            target: Settings
            function onBlurChanged() {
                window.applyBlur();
            }
            // Later, once panel.radius has caught up.
            function onAttachPanelsChanged() {
                Qt.callLater(window.applyBlur);
            }
            function onFlyoutRadiusChanged() {
                Qt.callLater(window.applyBlur);
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
            onActivated: root.close()
        }

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: panel

            // X-ray: the blurred wallpaper under the panel's colour.
            WallpaperBackdrop {
                window: window
                slideY: (1 - motion.progress) * 16
                onActiveChanged: window.applyBlur()
            }

            // Fades in while rising out of the bar; Settings > Appearance sets the speed.
            opacity: motion.progress
            transform: Translate {
                y: (1 - motion.progress) * 16
            }

            readonly property real pad: Theme.spacingS

            // Attached (Settings.attachPanels): sits on the taskbar like the
            // other flyouts, reaching Theme.flyoutOvershoot past it so its
            // bottom corners and border are off screen, with their corner
            // radius and border setting. Floating: a gap above the taskbar.
            readonly property real overshoot: Theme.flyoutOvershoot

            // Centred over the chevron, kept on screen.
            x: Math.max(Theme.spacingS, Math.min(Popouts.trayX - width / 2, parent.width - width - Theme.spacingS))
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.attachPanels ? -overshoot : Theme.spacingS
            width: grid.implicitWidth + pad * 2
            height: grid.implicitHeight + pad * 2 + overshoot
            radius: Theme.attachPanels ? Theme.flyoutRadius : Theme.cornerRadius
            color: Theme.popupBackground
            border.width: Theme.edgePanelBorder ? 1 : 0
            border.color: Theme.blurBorder

            // Swallows clicks so they don't close the panel.
            MouseArea {
                anchors.fill: parent
            }

            Grid {
                id: grid

                // Clear of the strip past the taskbar.
                anchors.horizontalCenter: parent.horizontalCenter
                y: panel.pad
                columns: Math.max(1, Math.min(6, root.items.length))
                spacing: Theme.spacingXS

                Repeater {
                    model: root.items

                    delegate: TrayIcon {
                        iconSize: root.iconSize
                        menuWindow: window
                        onActivated: root.close()
                    }
                }
            }
        }
    }
}
