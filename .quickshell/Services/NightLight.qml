pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Night light: a warmer screen through wl-gammarelay-rs, which sets niri's
// gamma over wlr-gamma-control and takes a new temperature over D-Bus while
// running. (wlsunset only read it at start, so every change restarted it
// and the screen went back to normal colours for a moment.) On/off is
// running the daemon or not.
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

    onTemperatureChanged: apply()

    // Sends the current temperature to the daemon. One call at a time; a
    // change made meanwhile goes out when it's done.
    property bool applyAgain: false
    property int applyTries: 0

    function apply() {
        if (!relay.running)
            return;
        if (setTemp.running) {
            applyAgain = true;
            return;
        }
        setTemp.command = ["busctl", "--user", "set-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Temperature", "q", String(temperature)];
        setTemp.running = true;
    }

    // Starts at 6500K (neutral); this sets the night light's temperature as
    // soon as it's up.
    Process {
        id: relay
        running: root.enabled
        command: ["wl-gammarelay-rs", "run"]
        onStarted: {
            root.applyTries = 0;
            root.apply();
        }
    }

    Process {
        id: setTemp
        onExited: code => {
            if (code !== 0 && root.applyTries < 30) {
                // Not on the bus yet: try again shortly.
                root.applyTries++;
                retry.restart();
                return;
            }
            root.applyTries = 0;
            if (root.applyAgain) {
                root.applyAgain = false;
                root.apply();
            }
        }
    }

    Timer {
        id: retry
        interval: 100
        onTriggered: root.apply()
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
