import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

// Port of the BetterClock DMS plugin (horizontal layout): fixed-width digits
// so the time doesn't jiggle as it changes, with the date right-aligned
// underneath. Settings are in Common/Config.qml.
//
// The plugin's click opened the DMS dash; there's no dash here yet, so the
// click just emits clockClicked for whatever you wire up later.
Item {
    id: root

    property real barThickness: Theme.barThickness
    signal clockClicked

    readonly property real padding: Theme.widgetPadding
    readonly property bool compact: Config.clockCompactMode

    implicitWidth: clockColumn.implicitWidth + padding * 2
    implicitHeight: barThickness

    component Digit: StyledText {
        font.pixelSize: clockColumn.fontSize
        width: clockColumn.digitWidth
        horizontalAlignment: Text.AlignHCenter
    }

    component Glyph: StyledText {
        font.pixelSize: clockColumn.fontSize
    }

    SystemClock {
        id: systemClock
        precision: Config.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse ? Theme.widgetHover : "transparent"
    }

    Column {
        id: clockColumn
        anchors.centerIn: parent
        spacing: 0

        readonly property real fontSize: Theme.barTextSize(root.barThickness)
        readonly property real digitWidth: fontSize * 0.6
        readonly property var date: systemClock.date

        readonly property string hoursStr: {
            const hours = date ? date.getHours() : 0;
            if (Config.use24HourClock)
                return String(hours).padStart(2, "0");
            const display = hours === 0 ? 12 : hours > 12 ? hours - 12 : hours;
            if (Config.padHours12Hour)
                return String(display).padStart(2, "0");
            return String(display);
        }
        readonly property string minutesStr: String(date ? date.getMinutes() : 0).padStart(2, "0")
        readonly property string secondsStr: String(date ? date.getSeconds() : 0).padStart(2, "0")
        readonly property string ampmStr: {
            if (Config.use24HourClock)
                return "";
            const hours = date ? date.getHours() : 0;
            return hours >= 12 ? " PM" : " AM";
        }

        Row {
            spacing: 0
            anchors.right: parent.right

            Digit {
                visible: clockColumn.hoursStr.length > 1
                text: clockColumn.hoursStr.charAt(0)
            }
            Digit {
                text: clockColumn.hoursStr.length > 1 ? clockColumn.hoursStr.charAt(1) : clockColumn.hoursStr.charAt(0)
            }
            Glyph {
                text: ":"
            }
            Digit {
                text: clockColumn.minutesStr.charAt(0)
            }
            Digit {
                text: clockColumn.minutesStr.charAt(1)
            }
            Glyph {
                visible: Config.showSeconds
                text: ":"
            }
            Digit {
                visible: Config.showSeconds
                text: clockColumn.secondsStr.charAt(0)
            }
            Digit {
                visible: Config.showSeconds
                text: clockColumn.secondsStr.charAt(1)
            }
            Glyph {
                visible: !Config.use24HourClock
                text: clockColumn.ampmStr
            }
        }

        StyledText {
            anchors.right: parent.right
            visible: !root.compact
            text: {
                const d = clockColumn.date;
                if (!d)
                    return "";
                const fmt = Config.clockDateFormat && Config.clockDateFormat.length > 0 ? Config.clockDateFormat : "ddd d";
                return d.toLocaleDateString(Qt.locale(), fmt);
            }
            font.pixelSize: Theme.fontSizeSmall * 0.8
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clockClicked()
    }
}
