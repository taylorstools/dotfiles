import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Full-screen power menu, a copy of Taylor's wlogout setup: six buttons in a
// row over the effects wallpaper (the dimmed, blurred one hyprlock uses),
// icons in matugen's light-scheme tertiary that grow and brighten on hover.
// Keys as in wlogout: L lock, E log out, Z sleep, S shut down, R reboot,
// W reboot into Windows; Esc closes.
//   qs ipc call powermenu toggle
Scope {
    id: root

    property bool shown: false

    readonly property var buttons: [
        {
            "icon": "lock",
            "text": "Lock",
            "key": "l",
            "run": () => Power.lock()
        },
        {
            "icon": "logout",
            "text": "Logout",
            "key": "e",
            "run": () => Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"])
        },
        {
            "icon": "sleep",
            "text": "Sleep",
            "key": "z",
            "run": () => Power.sleep()
        },
        {
            "icon": "shutdown",
            "text": "Shutdown",
            "key": "s",
            "run": () => Power.shutdown()
        },
        {
            "icon": "reboot",
            "text": "Reboot",
            "key": "r",
            "run": () => Power.restart()
        },
        {
            "icon": "windows",
            "text": "Windows",
            "key": "w",
            "run": () => Power.run("$HOME/scripts/refind_boot-to-windows.sh")
        }
    ]

    // wlogout's measurements: 230px around the grid (its row came out 25px
    // narrower than that, measured against screenshots), 10px around each
    // button, icons 60px (85px hovered), labels 63px above a button's bottom.
    readonly property real gridMargin: 230
    readonly property real gridShrink: 25
    readonly property real buttonMargin: 10
    readonly property real iconSize: 60
    readonly property real hoverIconSize: 85
    readonly property real labelLift: 63

    function open() {
        if (!motion.mapped) {
            const screens = Array.from(Quickshell.screens);
            window.screen = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        // The effects script rewrites the file when the wallpaper changes.
        background.source = "";
        background.source = "file://" + Quickshell.env("HOME") + "/.config/.EffectsWallpaper.png";
        shown = true;
    }

    function choose(button) {
        shown = false;
        button.run();
    }

    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            if (root.shown)
                root.shown = false;
            else
                root.open();
        }
        function open(): void {
            root.open();
        }
        function close(): void {
            root.shown = false;
        }
    }

    PanelMotion {
        id: motion
        shown: root.shown
    }

    // Label widths, so each button is its label plus an equal share of the
    // rest of the row, as GTK lays out wlogout's grid. Regular weight: wlogout
    // asked for "Inter Light", which GTK didn't find, and drew regular Inter.
    FontMetrics {
        id: labelMetrics
        font.family: Theme.fontFamily
        font.weight: Font.Normal
        font.pixelSize: 20
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
        // Over the taskbar too, like wlogout.
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "qstest:powermenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            id: content

            anchors.fill: parent
            opacity: motion.progress
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.shown = false;
                    event.accepted = true;
                    return;
                }
                const button = root.buttons.find(b => b.key === event.text.toLowerCase());
                if (button) {
                    root.choose(button);
                    event.accepted = true;
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            Image {
                id: background
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: false
            }

            // A click outside the buttons closes.
            MouseArea {
                anchors.fill: parent
                onClicked: root.shown = false
            }

            Row {
                id: grid

                readonly property real labelsWidth: root.buttons.reduce((sum, b) => sum + labelMetrics.advanceWidth(b.text), 0)
                readonly property real share: (width - labelsWidth) / root.buttons.length

                x: root.gridMargin
                y: root.gridMargin
                width: parent.width - root.gridMargin * 2 - root.gridShrink
                height: parent.height - root.gridMargin * 2

                Repeater {
                    model: root.buttons

                    delegate: Item {
                        id: cell

                        required property var modelData
                        readonly property bool hovered: cellMouse.containsMouse
                        property color tone: hovered ? Theme.tertiary : Theme.tertiaryLightScheme

                        width: labelMetrics.advanceWidth(modelData.text) + grid.share
                        height: grid.height

                        Behavior on tone {
                            ColorAnimation {
                                duration: 200
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            anchors.margins: root.buttonMargin
                            hoverEnabled: true
                            onClicked: root.choose(cell.modelData)
                        }

                        Image {
                            id: icon

                            property real size: cell.hovered ? root.hoverIconSize : root.iconSize

                            anchors.centerIn: parent
                            width: size
                            // Keeps the picture's shape (the lock is taller than wide).
                            height: implicitWidth > 0 ? size * implicitHeight / implicitWidth : size
                            source: "icons/" + cell.modelData.icon + ".png"
                            mipmap: true
                            visible: false

                            // wlogout's bounce: cubic-bezier(.55, 0, .28, 1.682) over 200 ms.
                            Behavior on size {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.55, 0.0, 0.28, 1.682, 1, 1]
                                }
                            }
                        }

                        // The icons are white; this paints them in the tone.
                        MultiEffect {
                            anchors.fill: icon
                            source: icon
                            colorization: 1
                            colorizationColor: cell.tone
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - root.buttonMargin - root.labelLift - height / 2
                            text: cell.modelData.text
                            color: cell.tone
                            font.weight: Font.Normal
                            font.pixelSize: 20
                        }
                    }
                }
            }
        }
    }
}
