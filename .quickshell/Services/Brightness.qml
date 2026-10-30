pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen backlight through brightnessctl, which goes through logind so it
// needs no root. sysfs brightness files don't send change events, so the
// level is polled from sysfs a few times a second; that's what lets the OSD
// notice changes made by anything else.
//   qs ipc -p <this folder> call brightness increment 5 | decrement 5
Singleton {
    id: root

    property bool available: false
    property string device: ""
    property real value: 0 // 0..1
    property int _max: 0

    property real _pending: 0
    property bool _writeAgain: false
    // While our own writes are landing, sysfs can still hold the old level.
    property double _lastSet: 0

    function refresh() {
        if (!reader.running)
            reader.running = true;
    }

    // Called on every slider move; while one brightnessctl call runs, only
    // the latest value is kept for the next one.
    function set(v) {
        _pending = Math.max(0.01, Math.min(1, v));
        value = _pending;
        _lastSet = Date.now();
        if (writer.running) {
            _writeAgain = true;
            return;
        }
        writer.command = ["brightnessctl", "-q", "-d", device, "set", Math.round(_pending * 100) + "%"];
        writer.running = true;
    }

    // Same steps as Taylor's old brightness script: going up rounds
    // down to the step first, so 47% + 5 lands on 50%.
    function increment(step) {
        const percent = Math.round(value * 100);
        set((Math.floor(percent / step) * step + step) / 100);
    }

    function decrement(step) {
        set((Math.round(value * 100) - step) / 100);
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // e.g. "amdgpu_bl1,backlight,400000,100%,400000"
                const fields = text.trim().split("\n")[0].split(",");
                const current = parseInt(fields[2]);
                const max = parseInt(fields[4]);
                root.available = fields.length >= 5 && max > 0;
                if (root.available) {
                    root.device = fields[0];
                    root._max = max;
                    root.value = current / max;
                }
            }
        }
    }

    Process {
        id: writer
        onExited: {
            if (root._writeAgain) {
                root._writeAgain = false;
                root.set(root._pending);
            }
        }
    }

    FileView {
        id: level
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            const raw = parseInt(text());
            if (isNaN(raw) || root._max <= 0 || writer.running || Date.now() - root._lastSet < 600)
                return;
            const v = raw / root._max;
            if (Math.abs(v - root.value) > 0.004)
                root.value = v;
        }
    }

    Timer {
        interval: 250
        running: root.available
        repeat: true
        onTriggered: level.reload()
    }

    IpcHandler {
        target: "brightness"

        function increment(step: int): void {
            root.increment(step > 0 ? step : 5);
        }
        function decrement(step: int): void {
            root.decrement(step > 0 ? step : 5);
        }
    }

    Component.onCompleted: refresh()
}
