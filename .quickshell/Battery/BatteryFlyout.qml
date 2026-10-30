import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The flyout behind the bar's battery: charge, time left and power draw,
// the power mode (power-profiles-daemon, as powerprofilesctl sets it) and,
// small at the bottom, the battery's health. Click the battery, or
//   qs ipc call battery toggle
//   qs ipc call battery setMode power-saver | balanced | performance
//   qs ipc call battery getMode
// Esc or a click outside closes it.
Scope {
    id: root

    readonly property bool shown: Popouts.batteryScreen !== null

    readonly property var modes: [
        {
            "id": "power-saver",
            "title": "Power saver",
            "icon": "eco"
        },
        {
            "id": "balanced",
            "title": "Balanced",
            "icon": "balance"
        },
        {
            "id": "performance",
            "title": "Performance",
            "icon": "bolt"
        }
    ]

    function close() {
        Popouts.batteryScreen = null;
    }

    onShownChanged: {
        if (shown)
            window.screen = Popouts.batteryScreen;
    }

    IpcHandler {
        target: "battery"

        function toggle(): void {
            if (root.shown) {
                root.close();
                return;
            }
            const screens = Array.from(Quickshell.screens);
            Popouts.toggleBattery(screens.find(s => s.name === Niri.focusedOutput) ?? screens[0]);
        }
        function close(): void {
            root.close();
        }
        function setMode(mode: string): void {
            BatteryInfo.setPowerMode(mode);
        }
        function getMode(): string {
            return BatteryInfo.powerMode;
        }
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

        WlrLayershell.namespace: "qstest:battery"
        WlrLayershell.layer: WlrLayer.Top
        // Exclusive, like the control center: with on-demand focus, a press on
        // the bar takes the keyboard away from the flyout, the shell has no
        // focused window for a moment, and Qt cancels the press - so clicking
        // another bar button while this was open needed a second click.
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                applyBlur();
        }

        Item {
            // Follows the panel as it rises out of the bar. Kept inside the
            // window: attached, the panel reaches past its bottom and right.
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
        // changes shape (corner radius).
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
                window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
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

            // Fades in while rising out of the bar; Settings > Appearance sets the speed.
            opacity: motion.progress
            transform: Translate {
                y: (1 - motion.progress) * 16
            }

            readonly property real pad: 16
            // Attached: reaches Theme.flyoutOvershoot past the taskbar and the
            // screen edge, so only the top-left corner is rounded and only the
            // top and left borders show. The content keeps clear of that strip.
            readonly property real overshoot: Theme.flyoutOvershoot

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.attachPanels ? -overshoot : Theme.spacingS
            width: Config.batteryFlyoutWidth + overshoot
            height: content.implicitHeight + pad * 2 + overshoot
            radius: Theme.flyoutRadius
            color: Theme.popupBackground
            border.width: Theme.edgePanelBorder ? 1 : 0
            border.color: Theme.blurBorder

            // Swallows clicks so they don't close the panel.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: panel.pad
                anchors.rightMargin: panel.pad + panel.overshoot
                anchors.bottomMargin: panel.pad + panel.overshoot
                spacing: 0

                // Charge, state, time left and power draw.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 26
                        color: Theme.withAlpha(Theme.primary, 0.15)

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: BatteryInfo.icon
                            size: 26
                            color: BatteryInfo.level < 10 && !BatteryInfo.charging ? Theme.error : Theme.primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            spacing: 8

                            StyledText {
                                text: BatteryInfo.level + "%"
                                font.pixelSize: 28
                                font.weight: Font.Medium
                                font.features: ({
                                        "tnum": 1
                                    })
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignBaseline
                                text: BatteryInfo.status
                                color: Theme.surfaceVariantText
                                font.pixelSize: 13
                            }
                        }

                        RowLayout {
                            spacing: 4
                            visible: timeText.text !== "" || BatteryInfo.rate > 0

                            StyledText {
                                id: timeText
                                visible: text !== ""
                                text: {
                                    if (BatteryInfo.timeLeft <= 0)
                                        return "";
                                    const t = BatteryInfo.formatTime(BatteryInfo.timeLeft);
                                    return BatteryInfo.charging ? "Full in " + t : "About " + t + " left";
                                }
                                color: Theme.surfaceVariantText
                                font.pixelSize: 13
                            }

                            StyledText {
                                visible: timeText.visible && BatteryInfo.rate > 0
                                text: "·"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 13
                            }

                            MaterialIcon {
                                visible: BatteryInfo.rate > 0
                                name: "bolt"
                                size: 15
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                visible: BatteryInfo.rate > 0
                                text: BatteryInfo.rate.toFixed(1) + " W"
                                color: Theme.surfaceVariantText
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                // Charge bar. The track is drawn from the text colour, so it
                // shows whatever the overlay opacity.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Theme.withAlpha(Theme.surfaceText, 0.12)

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, BatteryInfo.level / 100))
                        height: parent.height
                        radius: 3
                        color: BatteryInfo.level < 10 && !BatteryInfo.charging ? Theme.error : Theme.primary
                    }
                }

                // Power mode.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: 60
                    radius: 10
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        Repeater {
                            model: root.modes.filter(m => m.id !== "performance" || BatteryInfo.hasPerformance)

                            delegate: Rectangle {
                                id: modeButton

                                required property var modelData
                                readonly property bool current: BatteryInfo.powerMode === modelData.id

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 8
                                color: current ? Theme.primary : (modeMouse.containsMouse ? Theme.widgetHover : "transparent")

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    MaterialIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: modeButton.modelData.icon
                                        size: 20
                                        filled: modeButton.current
                                        color: modeButton.current ? Theme.onPrimary : Theme.surfaceText
                                    }

                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modeButton.modelData.title
                                        color: modeButton.current ? Theme.onPrimary : Theme.surfaceText
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    id: modeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BatteryInfo.setPowerMode(modeButton.modelData.id)
                                }
                            }
                        }
                    }
                }

                // Health: small, so it isn't read as the charge level.
                RowLayout {
                    Layout.topMargin: 12
                    visible: BatteryInfo.health > 0
                    spacing: 6

                    MaterialIcon {
                        name: "monitor_heart"
                        size: 15
                        color: Theme.outline
                    }

                    StyledText {
                        text: "Battery health " + BatteryInfo.health + "%"
                        color: Theme.outline
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
