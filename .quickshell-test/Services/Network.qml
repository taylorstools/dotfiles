pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi / ethernet state from nmcli. `nmcli monitor` triggers a refresh on any
// NetworkManager change; a slow timer catches signal-strength drift.
Singleton {
    id: root

    property bool available: false
    property bool ethernet: false
    property bool wifiEnabled: false
    property bool wifiConnected: false
    property int wifiSignal: 0

    readonly property string icon: {
        if (!available)
            return "";
        if (ethernet)
            return "lan";
        // Same thresholds and glyphs as DMS.
        if (!wifiEnabled || !wifiConnected)
            return "wifi_off";
        if (wifiSignal >= 50)
            return "wifi";
        if (wifiSignal >= 25)
            return "wifi_2_bar";
        return "wifi_1_bar";
    }

    function refresh() {
        if (!poll.running)
            poll.running = true;
    }

    Process {
        id: poll
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device && echo --- && nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                const devices = (parts[0] || "").trim().split("\n").filter(l => l);
                let eth = false;
                let wifiOn = false;
                let wifiUp = false;
                for (const line of devices) {
                    const [type, state] = line.split(":");
                    if (type === "ethernet" && state === "connected")
                        eth = true;
                    if (type === "wifi") {
                        if (state !== "unavailable" && state !== "unmanaged")
                            wifiOn = true;
                        if (state === "connected")
                            wifiUp = true;
                    }
                }
                let signal = 0;
                for (const line of (parts[1] || "").trim().split("\n")) {
                    if (line.startsWith("*:"))
                        signal = parseInt(line.slice(2)) || 0;
                }
                root.available = devices.length > 0;
                root.ethernet = eth;
                root.wifiEnabled = wifiOn;
                root.wifiConnected = wifiUp;
                root.wifiSignal = signal;
            }
        }
    }

    Process {
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: _ => debounce.restart()
        }
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
