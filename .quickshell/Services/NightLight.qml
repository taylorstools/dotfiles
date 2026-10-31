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

    // Set by hand rather than bound: a daemon that exits is started again
    // below, and assigning `running` from JS would break a binding.
    onEnabledChanged: {
        relay.quickExits = 0;
        relay.running = enabled;
    }
    Component.onCompleted: relay.running = enabled

    // Starts at 6500K (neutral); this sets the night light's temperature as
    // soon as it's up.
    Process {
        id: relay

        property double startedAt: 0
        property int quickExits: 0

        command: ["wl-gammarelay-rs", "run"]
        onStarted: {
            startedAt = Date.now();
            root.applyTries = 0;
            root.apply();
        }
        // On a config reload the new daemon starts while the old one still
        // holds the bus name and quits, then the old one is stopped; a crash
        // ends it too. Either way, while night light is on, start it again.
        onExited: {
            if (!root.enabled)
                return;
            quickExits = Date.now() - startedAt < 5000 ? quickExits + 1 : 0;
            if (quickExits <= 10)
                relaunch.restart();
            else
                console.warn("NightLight: wl-gammarelay-rs keeps exiting; giving up until night light is toggled");
        }
    }

    Timer {
        id: relaunch
        interval: 1000
        onTriggered: {
            if (root.enabled && !relay.running)
                relay.running = true;
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
