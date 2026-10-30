import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets

// The network / bluetooth / volume cluster that the control-center button
// shows. Click opens the control center on this bar's screen, scroll changes
// the volume, middle click toggles mute.
Item {
    id: root

    property real barThickness: Theme.barThickness
    property var parentScreen: null
    readonly property bool open: Popouts.controlCenterScreen !== null && Popouts.controlCenterScreen === parentScreen

    // The -4 icon offset: 16 px on your bar.
    readonly property real iconSize: Theme.barIconSize(barThickness, false, -4)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btConnected: (Bluetooth.devices ? Bluetooth.devices.values : []).some(d => d.connected)
    readonly property string btIcon: {
        if (!adapter)
            return "";
        if (!adapter.enabled)
            return "bluetooth_disabled";
        return "bluetooth";
    }

    readonly property string volumeIcon: {
        if (!audio)
            return "volume_off";
        if (audio.muted)
            return "volume_off";
        if (audio.volume === 0)
            return "volume_mute";
        return audio.volume <= 0.33 ? "volume_down" : "volume_up";
    }

    implicitWidth: row.implicitWidth + Theme.widgetPadding * 2
    implicitHeight: barThickness

    PwObjectTracker {
        objects: [root.sink]
    }

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse || root.open ? Theme.widgetHover : "transparent"
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        MaterialIcon {
            visible: Network.icon !== ""
            name: Network.icon
            size: root.iconSize
        }

        MaterialIcon {
            visible: root.btIcon !== ""
            name: root.btIcon
            size: root.iconSize
            filled: root.btConnected
            color: root.btConnected ? Theme.primary : Theme.widgetText
        }

        // The audio group: the icon 1 px in from each side.
        Item {
            width: root.iconSize + 2
            height: root.iconSize

            MaterialIcon {
                x: 1
                name: root.volumeIcon
                size: root.iconSize
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                Popouts.toggleControlCenter(root.parentScreen);
            else if (root.audio)
                root.audio.muted = !root.audio.muted;
        }
        onWheel: wheel => {
            if (!root.audio)
                return;
            const step = 0.05 * (wheel.angleDelta.y > 0 ? 1 : -1);
            root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + step));
            wheel.accepted = true;
        }
    }

    Tooltip {
        target: root
        shown: mouse.containsMouse && !root.open
        text: root.audio ? ("Volume " + Math.round(root.audio.volume * 100) + "%" + (root.audio.muted ? " (muted)" : "")) : ""
    }
}
