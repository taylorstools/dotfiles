pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Night light: a warmer screen through wlsunset, which
// sets niri's gamma over wlr-gamma-control. wlsunset schedules a day and a
// night temperature; giving it two only 1K apart keeps the screen at the
// chosen warmth around the clock, so on/off is just running it or not.
//   qs ipc call night toggle | enable | disable | status
//   qs ipc call night getTemp | setTemp 3000
Singleton {
    id: root

    readonly property bool enabled: Settings.nightLight
    readonly property int temperature: Math.max(1000, Math.min(6500, Number(Settings.nightLightTemperature) || 3000))

    function setEnabled(on) {
        Settings.nightLight = on;
    }

    function setTemperature(kelvin) {
        Settings.nightLightTemperature = Math.round(Math.max(1000, Math.min(6500, kelvin)));
    }

    // wlsunset reads its temperatures once, so a new one means a restart:
    // `restarting` stops it for a moment. Never assign sunset.running
    // directly; that would break its binding to `enabled`, and turning night
    // light off would then leave wlsunset running.
    property bool restarting: false

    onTemperatureChanged: {
        if (sunset.running) {
            restarting = true;
            restart.restart();
        }
    }

    Timer {
        id: restart
        interval: 100
        onTriggered: root.restarting = false
    }

    Process {
        id: sunset
        running: root.enabled && !root.restarting
        command: ["wlsunset", "-t", String(root.temperature), "-T", String(root.temperature + 1), "-S", "06:00", "-s", "18:00", "-d", "1"]
    }

    IpcHandler {
        target: "night"

        function toggle(): void {
            root.setEnabled(!root.enabled);
        }
        function enable(): void {
            root.setEnabled(true);
        }
        function disable(): void {
            root.setEnabled(false);
        }
        function status(): string {
            return root.enabled ? "enabled" : "disabled";
        }
        function getTemp(): int {
            return root.temperature;
        }
        function setTemp(kelvin: int): void {
            root.setTemperature(kelvin);
        }
    }
}
