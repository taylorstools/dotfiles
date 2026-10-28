import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets

// The network / bluetooth / volume cluster that DMS's control-center button
// shows. There's no control center behind it yet: scroll changes the
// volume, middle click toggles mute.
Item {
    id: root

    property real barThickness: Theme.barThickness

    readonly property real iconSize: Theme.barIconSize(barThickness, false)
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
        color: mouse.containsMouse ? Theme.widgetHover : "transparent"
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

        MaterialIcon {
            name: root.volumeIcon
            size: root.iconSize
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.MiddleButton
        onClicked: {
            if (root.audio)
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
        shown: mouse.containsMouse
        text: root.audio ? ("Volume " + Math.round(root.audio.volume * 100) + "%" + (root.audio.muted ? " (muted)" : "")) : ""
    }
}
