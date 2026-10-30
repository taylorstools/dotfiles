pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi / ethernet state from nmcli. `nmcli monitor` triggers a refresh on any
// NetworkManager change; a slow timer catches signal-strength drift.
// While `listNetworks` is set (the control center is open) a refresh also
// reads the visible Wi-Fi networks, and connect/disconnect go through here.
Singleton {
    id: root

    property bool available: false
    property bool ethernet: false
    property bool wifiEnabled: false
    property bool wifiConnected: false
    property int wifiSignal: 0
    property string wifiDevice: ""

    property bool listNetworks: false
    // Strongest first: [{ ssid, signal, secure, active, saved }]
    property var networks: []
    property bool scanning: false
    property string connectingSsid: ""
    property string lastError: ""
    // Set when a saved network fails to connect (most often because its
    // password changed); the control center then asks for a new one.
    property string passwordNeeded: ""
    property var _savedNames: []

    readonly property string icon: {
        if (!available)
            return "";
        if (ethernet)
            return "lan";
        if (!wifiEnabled || !wifiConnected)
            return "wifi_off";
        return signalIcon(wifiSignal);
    }

    // Signal thresholds for the Material Symbols wifi glyphs.
    function signalIcon(signal) {
        if (signal >= 50)
            return "wifi";
        if (signal >= 25)
            return "wifi_2_bar";
        return "wifi_1_bar";
    }

    function refresh() {
        if (!poll.running)
            poll.running = true;
        if (listNetworks && !scanning)
            readNetworks(false);
    }

    // A rescan takes a few seconds; `scanning` is true until it's done.
    function scan() {
        readNetworks(true);
    }

    function readNetworks(rescan) {
        if (lister.running)
            return;
        scanning = rescan;
        lister.command = ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan " + (rescan ? "yes" : "no") + " && echo --- && nmcli -t -f NAME,TYPE connection show"];
        lister.running = true;
    }

    // Saved networks reconnect with their stored secrets; new ones go through
    // `device wifi connect`, which saves them. The password is briefly
    // visible in nmcli's argv, as with any nmcli-based applet.
    function connect(ssid, password) {
        lastError = "";
        passwordNeeded = "";
        connectingSsid = ssid;
        const saved = _savedNames.includes(ssid);
        if (saved && !password) {
            // If this fails, ask for the password again.
            runAction(["nmcli", "connection", "up", "id", ssid], "", ssid);
        } else if (saved) {
            // A new password for a saved network: update its profile, then
            // connect, so it keeps its other settings.
            runAction(["sh", "-c", 'nmcli connection modify id "$1" wifi-sec.psk "$2" && nmcli connection up id "$1"', "sh", ssid, password], "", ssid);
        } else {
            const cmd = ["nmcli", "device", "wifi", "connect", ssid];
            if (password)
                cmd.push("password", password);
            // A failed first connect still leaves a saved profile with the
            // wrong password behind; remove it so the next try asks again.
            runAction(cmd, ssid, "");
        }
    }

    function disconnect() {
        lastError = "";
        if (wifiDevice)
            runAction(["nmcli", "device", "disconnect", wifiDevice], "");
    }

    // Deletes the saved profile (and its password); if it's the network in
    // use, that disconnects too.
    function forget(ssid) {
        lastError = "";
        if (passwordNeeded === ssid)
            passwordNeeded = "";
        runAction(["nmcli", "connection", "delete", "id", ssid], "");
    }

    function setWifiEnabled(on) {
        lastError = "";
        runAction(["nmcli", "radio", "wifi", on ? "on" : "off"], "");
    }

    function runAction(cmd, forgetOnFailure, askOnFailure) {
        if (action.running)
            return;
        action.forgetOnFailure = forgetOnFailure;
        action.askOnFailure = askOnFailure ?? "";
        action.command = cmd;
        action.running = true;
    }

    // nmcli -t escapes ':' and '\' inside fields with a backslash.
    function splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    Process {
        id: poll
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device && echo --- && nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                const devices = (parts[0] || "").trim().split("\n").filter(l => l);
                let eth = false;
                let wifiOn = false;
                let wifiUp = false;
                let wifiDev = "";
                for (const line of devices) {
                    const [device, type, state] = root.splitTerse(line);
                    if (type === "ethernet" && state === "connected")
                        eth = true;
                    if (type === "wifi") {
                        wifiDev = device;
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
                root.wifiDevice = wifiDev;
            }
        }
    }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---\n");
                const saved = [];
                for (const line of (parts[1] || "").trim().split("\n")) {
                    const [name, type] = root.splitTerse(line);
                    if (type === "802-11-wireless")
                        saved.push(name);
                }
                // One entry per SSID: access points of the same network are merged.
                const bySsid = {};
                for (const line of (parts[0] || "").trim().split("\n")) {
                    const [inUse, signal, security, ssid] = root.splitTerse(line);
                    if (!ssid)
                        continue;
                    const entry = bySsid[ssid] ?? {
                        ssid: ssid,
                        signal: 0,
                        secure: false,
                        active: false,
                        saved: saved.includes(ssid)
                    };
                    entry.signal = Math.max(entry.signal, parseInt(signal) || 0);
                    entry.secure = entry.secure || (security !== "" && security !== "--");
                    entry.active = entry.active || inUse === "*";
                    bySsid[ssid] = entry;
                }
                root._savedNames = saved;
                root.networks = Object.values(bySsid).sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
            }
        }
        onExited: root.scanning = false
    }

    Process {
        id: action

        property string forgetOnFailure: ""
        property string askOnFailure: ""

        stderr: StdioCollector {
            id: actionErr
        }
        onExited: code => {
            if (code !== 0) {
                const message = actionErr.text.trim().replace(/^Error:\s*/, "");
                root.lastError = message || "nmcli failed";
                if (forgetOnFailure)
                    Quickshell.execDetached(["nmcli", "connection", "delete", "id", forgetOnFailure]);
                if (askOnFailure)
                    root.passwordNeeded = askOnFailure;
            }
            root.connectingSsid = "";
            root.refresh();
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
