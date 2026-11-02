pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Webcam privacy switch for the camera key. Off deauthorizes every USB video
// interface (class 0e), so no app can open the camera until it's switched
// back on; on authorizes them again and re-probes them, since authorizing
// alone doesn't rebind uvcvideo. Only interfaces whose `authorized` file we
// may write count: quickshell.nix's udev rule grants that, and drivers_probe
// too. The rest of the webcam (the PX13's light and presence sensors) stays
// up. Every boot starts with the camera on.
//   qs ipc call camera toggle | on | off | status
Singleton {
    id: root

    // "on", "off", "none" (nothing we may switch), or "" until first read.
    property string status: ""
    // A switch asked for while another was being written ("on"/"off").
    // Toggling goes from where the camera is heading, not from `status`, so
    // quick presses each flip it instead of repeating the last one.
    property string _queued: ""

    // After each switch, from its own result; for the OSD toast.
    signal switched(string status, bool failed)

    // Each line of output: one interface's sysfs dir.
    readonly property string listScript: 'for d in /sys/bus/usb/devices/*:*; do [ "$(cat "$d/bInterfaceClass" 2>/dev/null)" = 0e ] && [ -w "$d/authorized" ] && echo "$d"; done; true'

    function set(on) {
        _queued = on ? "on" : "off";
        writeQueued();
    }

    function toggle() {
        const heading = _queued || (writer.running ? writer.target : status);
        set(heading !== "on");
    }

    function writeQueued() {
        if (writer.running || _queued === "")
            return;
        writer.target = _queued;
        _queued = "";
        writer.command = ["sh", "-c", 'ifaces=$(' + listScript + ')
[ -n "$ifaces" ] || exit 3
for d in $ifaces; do echo "$1" > "$d/authorized" || exit 1; done
if [ "$1" = 1 ]; then
    for d in $ifaces; do printf %s "${d##*/}" > /sys/bus/usb/drivers_probe; done
fi
true', "sh", writer.target === "on" ? "1" : "0"];
        writer.running = true;
    }

    Component.onCompleted: reader.running = true

    Process {
        id: reader
        command: ["sh", "-c", 'ifaces=$(' + root.listScript + '); [ -n "$ifaces" ] || { echo none; exit; }; for d in $ifaces; do [ "$(cat "$d/authorized")" = 0 ] && { echo off; exit; }; done; echo on']
        stdout: StdioCollector {
            onStreamFinished: root.status = text.trim()
        }
    }

    Process {
        id: writer

        property string target: ""

        onExited: code => {
            if (code === 0) {
                root.status = target;
                root.switched(target, false);
            } else {
                if (code === 3)
                    root.status = "none";
                root.switched(root.status, true);
                // Half switched, maybe: find out where it stands.
                reader.running = true;
            }
            root.writeQueued();
        }
    }

    IpcHandler {
        target: "camera"

        function toggle(): void {
            root.toggle();
        }
        function on(): void {
            root.set(true);
        }
        function off(): void {
            root.set(false);
        }
        function status(): string {
            return root.status;
        }
    }
}
