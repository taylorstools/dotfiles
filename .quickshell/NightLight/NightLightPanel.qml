import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// "Night Mode Strength": a slider for the night light's warmth, the
// replacement for scripts/night-light-temperature.sh and its yad dialog.
// Opening it turns the night light on. 6000K on the left to 2500K on the
// right, 100K a step (the arrow keys too); the temperature follows the
// slider as it moves. Esc, Enter, Close or a click outside closes it.
//   qs ipc call nightpanel toggle      (Key press menu: N)
Scope {
    id: root

    property bool shown: false
    // What the slider shows; NightLight catches up shortly after (see apply).
    property int pending: NightLight.temperature

    readonly property int minK: 2500
    readonly property int maxK: 6000

    function show() {
        if (!motion.mapped) {
            const screens = Array.from(Quickshell.screens);
            window.screen = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        NightLight.setEnabled(true);
        pending = Math.max(minK, Math.min(maxK, NightLight.temperature));
        shown = true;
    }

    function hide() {
        // A move still waiting on the timer lands now.
        if (apply.running) {
            apply.stop();
            NightLight.setTemperature(pending);
        }
        shown = false;
    }

    function setPending(kelvin) {
        pending = kelvin;
        apply.restart();
    }

    // A drag sends the latest temperature at most every 50 ms rather than
    // one per step (each is also saved to settings.json).
    Timer {
        id: apply
        interval: 50
        onTriggered: NightLight.setTemperature(root.pending)
    }

    IpcHandler {
        target: "nightpanel"

        function toggle(): void {
            if (root.shown)
                root.hide();
            else
                root.show();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
    }

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

        WlrLayershell.namespace: "qstest:nightpanel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                slider.forceActiveFocus();
                applyBlur();
            }
        }

        Item {
            // Follows the panel's open/close scaling, so the blur grows with it.
            Region {
                id: blurRegion
                x: panel.x + panel.width * (1 - panel.scale) / 2
                y: panel.y + panel.height * (1 - panel.scale) / 2
                width: panel.width * panel.scale
                height: panel.height * panel.scale
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

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Shortcut {
            sequences: ["Escape", "Return", "Enter"]
            enabled: root.shown
            onActivated: root.hide()
        }

        Rectangle {
            id: panel

            // X-ray: the blurred wallpaper under the panel's colour.
            WallpaperBackdrop {
                window: window
                onActiveChanged: window.applyBlur()
            }

            // Fades and grows in from 95%; Settings > Appearance sets the speed.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

            readonly property real pad: Theme.spacingL

            anchors.centerIn: parent
            width: 440
            height: content.implicitHeight + pad * 2
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallows clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: panel.pad
                spacing: Theme.spacingM

                RowLayout {
                    spacing: Theme.spacingS

                    MaterialIcon {
                        name: "nightlight"
                        size: 22
                        filled: true
                        color: Theme.primary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Night Mode Strength"
                        font.pixelSize: Theme.fontSizeLarge
                    }

                    StyledText {
                        text: root.pending + "K"
                        color: Theme.surfaceVariantText
                    }
                }

                // Right is warmer, as the yad slider was.
                StyledSlider {
                    id: slider
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingS
                    focus: true
                    value: (root.maxK - root.pending) / (root.maxK - root.minK)
                    steps: (root.maxK - root.minK) / 100
                    onMoved: v => root.setPending(Math.round((root.maxK - v * (root.maxK - root.minK)) / 100) * 100)
                }

                RowLayout {
                    StyledText {
                        Layout.fillWidth: true
                        text: root.maxK + "K"
                        color: Theme.outline
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: root.minK + "K"
                        color: Theme.outline
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                RowLayout {
                    Layout.topMargin: Theme.spacingXS

                    Item {
                        Layout.fillWidth: true
                    }

                    IconButton {
                        implicitHeight: 34
                        text: "Close"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: root.hide()
                    }
                }
            }
        }
    }
}
