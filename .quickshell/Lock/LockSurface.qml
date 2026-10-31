import QtQuick
import Quickshell
import qs.Common
import qs.Services

// What one screen of the lock shows, a copy of Taylor's hyprlock.conf
// (dot_config/hypr before the switch): the effects wallpaper, date and time,
// the user, the password field, battery bottom left and power icons bottom
// right. Placement and sizes follow hyprlock's, which counts in physical
// pixels and font points without the output scale; hp() and fp() convert.
Item {
    id: root

    // The Lock scope: password, state and actions are shared by every screen.
    required property var lock
    // Off for the copy that fades in and out (Lock.qml): it shows the lock
    // as it stands, without replaying the dots' typing animations.
    property bool animated: true

    // matugen's tertiary in the light and dark scheme ($light and $lighter
    // in hyprlock.conf).
    readonly property color light: Theme.tertiaryLightScheme
    readonly property color lighter: Theme.tertiary
    readonly property real dpr: Window.window?.devicePixelRatio ?? Theme.dpr

    function hp(physical) {
        return physical / dpr;
    }
    function fp(points) {
        return points * 4 / 3 / dpr;
    }

    // Keyboard goes to the field; it's invisible, the dots below show it.
    function focusInput() {
        input.forceActiveFocus();
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: root.lock.backgroundSource
        cache: false
    }

    // Date: 42pt, top edge at 23% down.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.23
        text: Qt.formatDate(clock.date, "dddd, MMMM d")
        color: root.light
        font.family: "Inter Display"
        font.weight: Font.ExtraLight
        font.pixelSize: root.fp(42)
    }

    // Time: 180pt, top edge at 26% down.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.26
        text: Qt.formatTime(clock.date, "h:mm")
        color: root.lighter
        font.family: "Inter Display"
        font.weight: Font.ExtraLight
        font.pixelSize: root.fp(180)
    }

    // User: 48pt, bottom edge at 32% up.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.68 - height
        text: "\uf2be   " + root.lock.userName
        color: root.lighter
        font.family: "Inter Display"
        font.weight: Font.ExtraLight
        font.pixelSize: root.fp(48)
    }

    // Password field: 18% x 5% of the screen, bottom edge at 25% up, and
    // around that a 2px outline fading from $lighter at the top to $light at
    // the bottom.
    Item {
        id: field

        readonly property real outlineWidth: root.hp(2)

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.75 + outlineWidth - height
        width: parent.width * 0.18 + outlineWidth * 2
        height: parent.height * 0.05 + outlineWidth * 2

        Canvas {
            id: outline

            // Eases to check_color (rgb(800020) to rgb(D22B2B)) while the
            // password is being checked, and back. Only once a check has
            // taken a moment (Lock.showChecking): a right password, answered
            // at once, would otherwise flash red as if it were wrong.
            property real checking: root.lock.showChecking ? 1 : 0
            Behavior on checking {
                // Accepted: snap back rather than fade from red.
                enabled: !root.lock.unlocking
                NumberAnimation {
                    duration: 200
                }
            }
            onCheckingChanged: requestPaint()

            function mix(a, b, t) {
                return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
            }

            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = field.outlineWidth;
                const r = (height - w) / 2;
                ctx.beginPath();
                ctx.roundedRect(w / 2, w / 2, width - w, height - w, r, r);
                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.5);
                ctx.fill();
                const g = ctx.createLinearGradient(0, 0, 0, height);
                g.addColorStop(0, mix(root.lighter, Qt.color("#d22b2b"), checking));
                g.addColorStop(1, mix(root.light, Qt.color("#800020"), checking));
                ctx.lineWidth = w;
                ctx.strokeStyle = g;
                ctx.stroke();
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: root
                function onLightChanged() {
                    outline.requestPaint();
                }
                function onLighterChanged() {
                    outline.requestPaint();
                }
            }
        }

        // "Password" with a lock while empty, "Try again" after a wrong one,
        // nothing while it's being checked.
        Row {
            anchors.centerIn: parent
            visible: root.lock.password === "" && root.lock.authState !== "checking"

            // Inter has no lock; this is the Nerd Font one hyprlock fell back to.
            Text {
                visible: root.lock.authState !== "failed"
                text: "\uf023"
                color: root.light
                font.family: "JetBrainsMono Nerd Font Mono"
                font.pixelSize: root.hp(28)
            }

            Text {
                text: root.lock.authState === "failed" ? "Try again" : "    Password"
                color: root.light
                font.family: "Inter"
                font.weight: Font.Light
                font.pixelSize: root.hp(28)
            }
        }

        // One dot per character, 20% of the field's height, half a dot apart.
        // They stay while the password is checked, as hyprlock's do. Matched
        // frame by frame to a recording of hyprlock: the newest dot fades in
        // on Hyprland's default curve (fast, then a long tail) and snaps to
        // full when the next key comes; the row glides to re-centre on the
        // same curve.
        Item {
            id: dots

            readonly property real dotSize: field.height * 0.2
            readonly property real step: dotSize * 1.5
            readonly property int count: root.lock.password.length

            // Centred, plus `glideOffset` while the row glides after a key.
            // Only a key moves it: when this lock screen is new its field has
            // no width yet, and animating x itself glided the dots in from
            // the left edge once the width arrived.
            x: (field.width - (count > 0 ? count * step - dotSize * 0.5 : 0)) / 2 + glideOffset
            anchors.verticalCenter: parent.verticalCenter
            height: dotSize

            property real glideOffset: 0
            property int lastCount: 0

            Component.onCompleted: lastCount = count
            onCountChanged: {
                // Starts where the row was, then eases back to centre. An
                // emptied field (a wrong password) starts the next one afresh.
                if (count === 0) {
                    glide.stop();
                    glideOffset = 0;
                } else if (root.animated) {
                    glideOffset += (count - lastCount) * step / 2;
                    glide.restart();
                }
                lastCount = count;
            }

            NumberAnimation {
                id: glide
                target: dots
                property: "glideOffset"
                to: 0
                duration: 1200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.05, 0.9, 0.1, 1.05, 1, 1]
            }

            Repeater {
                model: dots.count

                delegate: Rectangle {
                    required property int index
                    property real appear: root.animated ? 0 : 1

                    x: index * dots.step
                    width: dots.dotSize
                    height: width
                    radius: width / 2
                    color: root.lighter
                    opacity: index < dots.count - 1 ? 1 : Math.min(1, appear)

                    NumberAnimation on appear {
                        running: root.animated
                        from: 0
                        to: 1
                        duration: 1300
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.05, 0.9, 0.1, 1.05, 1, 1]
                    }
                }
            }
        }

        TextInput {
            id: input

            opacity: 0
            width: 1
            height: 1
            focus: true
            echoMode: TextInput.Password
            // Nothing to edit while it's being checked: the dots stay put.
            readOnly: root.lock.authState === "checking"
            text: root.lock.password
            onTextEdited: root.lock.password = text
            onAccepted: root.lock.submit()
            // Clears the field; closes the preview.
            Keys.onEscapePressed: {
                if (root.lock.previewing)
                    root.lock.previewing = false;
                else
                    root.lock.password = "";
            }
        }
    }

    // Battery: 32pt, left edge 47px in, bottom edge 34px up.
    Text {
        x: root.hp(47)
        y: parent.height - root.hp(34) - height
        text: root.lock.batteryText
        visible: BatteryInfo.present
        color: root.light
        font.family: "Inter Display"
        font.weight: Font.ExtraLight
        font.pixelSize: root.fp(32)
    }

    // Power icons, JetBrainsMono Nerd Font: right edges 290/210/130/50px in.
    Repeater {
        model: [
            {
                "glyph": "\uf28c",
                "size": 52,
                "right": 290,
                "bottom": 17,
                "command": "systemctl suspend"
            },
            {
                "glyph": "\u{f0425}",
                "size": 48,
                "right": 210,
                "bottom": 20,
                "command": "systemctl poweroff"
            },
            {
                "glyph": "\uead2",
                "size": 48,
                "right": 130,
                "bottom": 20,
                "command": "systemctl reboot"
            },
            {
                "glyph": "\u{f05b3}",
                "size": 48,
                "right": 50,
                "bottom": 20,
                "command": "$HOME/scripts/refind_boot-to-windows.sh"
            }
        ]

        delegate: Text {
            id: powerIcon

            required property var modelData

            x: root.width - root.hp(modelData.right) - width
            y: root.height - root.hp(modelData.bottom) - height
            text: modelData.glyph
            // Brightens under the pointer, like the power menu's icons.
            color: powerMouse.containsMouse ? root.lighter : root.light
            font.family: "JetBrainsMono Nerd Font Mono"
            font.pixelSize: root.fp(modelData.size)

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            MouseArea {
                id: powerMouse
                // A little larger than the glyph, so it's easy to hit.
                anchors.fill: parent
                anchors.margins: -root.hp(8)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["sh", "-c", powerIcon.modelData.command])
            }
        }
    }
}
