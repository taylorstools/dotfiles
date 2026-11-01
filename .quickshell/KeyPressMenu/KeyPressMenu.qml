import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Key press menu, the replacement for wlr-which-key: a list of keys, each
// running a command. Press a key to run its command; Esc, a click outside or
// a key with no entry does nothing but close. Keys in the monospace font,
// descriptions in the normal one (Settings > Appearance). The entries are on
// the settings window's Key press menu page (Settings.keyPressEntries).
//   qs ipc call keypress toggle      (Mod+X)
Scope {
    id: root

    property bool shown: false
    readonly property var entries: (Settings.keyPressEntries ?? []).filter(e => (e.key ?? "") !== "")

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            window.screen = target;
        shown = true;
    }

    function hide() {
        shown = false;
    }

    function run(entry) {
        hide();
        if ((entry.cmd ?? "").trim() !== "")
            Quickshell.execDetached(["sh", "-c", entry.cmd]);
    }

    IpcHandler {
        target: "keypress"

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

        WlrLayershell.namespace: "qstest:keypress"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                keys.forceActiveFocus();
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

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                if (!root.shown)
                    return;
                event.accepted = true;
                // Bare modifiers (Shift for a capital) wait for the key itself.
                if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta)
                    return;
                const entry = root.entries.find(e => e.key === event.text);
                if (entry)
                    root.run(entry);
                else
                    root.hide();
            }
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

            readonly property real pad: 25

            anchors.centerIn: parent
            width: list.implicitWidth + pad * 2
            height: list.implicitHeight + pad * 2
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallows clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: list

                anchors.centerIn: parent
                // As wide as the widest row, so every row's hover fills it.
                width: Math.max(0, ...Array.from(children).map(c => c.implicitWidth ?? 0))
                spacing: 2

                Repeater {
                    model: root.entries

                    delegate: Rectangle {
                        id: row

                        required property var modelData

                        width: list.width
                        implicitWidth: line.implicitWidth + Theme.spacingS * 2
                        height: line.implicitHeight + 4
                        radius: 6
                        color: rowMouse.containsMouse ? Theme.widgetHover : "transparent"

                        Row {
                            id: line

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.baseline: desc.baseline
                                text: row.modelData.key
                                color: Theme.primary
                                font.family: Theme.monoFamily
                                font.pixelSize: 16
                                renderType: Text.NativeRendering
                            }

                            Text {
                                anchors.baseline: desc.baseline
                                text: " ➜ "
                                color: Theme.surfaceVariantText
                                font.family: Theme.monoFamily
                                font.pixelSize: 16
                                renderType: Text.NativeRendering
                            }

                            StyledText {
                                id: desc
                                text: row.modelData.desc ?? ""
                                font.pixelSize: 16
                            }
                        }

                        // A click runs it too.
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.run(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
