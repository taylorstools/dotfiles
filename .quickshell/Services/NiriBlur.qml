pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Blur strength isn't the shell's to draw: niri blurs everything with one
// `blur { passes; offset }` block in its config. This writes that block to a
// file of its own whenever Settings.blurStrength changes (offset =
// strength / 14, 3 passes). niri only uses it once config.kdl includes the
// file; `included` says whether that line is there.
//
// niri ignores the blur protocol on normal windows, so the settings window
// (a FloatingWindow) only blurs through a window rule. That rule lives here
// too, so Settings.blur switches it on and off with the panels.
//
// X-ray (Settings.blurXray) is niri's too: a layer rule for every qstest:
// surface, and the same flag on the settings window's rule.
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qstest"
    readonly property string path: stateDir + "/niri-blur.kdl"
    readonly property string includeLine: "include \"" + path + "\""
    readonly property string niriConfig: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/niri/config.kdl"
    property bool included: false

    function contents(strength, blur, xray) {
        let text = "// Written by the qstest Quickshell config (Settings > Appearance).\n// Changes here are overwritten.\n";
        // 0 leaves blur to niri's own default.
        if (strength > 0)
            text += "blur {\n    passes 3\n    offset " + (Math.round(strength / 14 * 10) / 10) + "\n}\n";
        if (blur) {
            const x = xray ? "true" : "false";
            text += "layer-rule {\n    match namespace=\"^qstest:\"\n    background-effect {\n        xray " + x + "\n    }\n}\n";
            text += "window-rule {\n    match app-id=\"^org.quickshell$\" title=\"^Shell Settings$\"\n    background-effect {\n        blur true\n        xray " + x + "\n    }\n}\n";
        }
        return text;
    }

    // Called from shell.qml so the file exists from startup on.
    function ensureWritten() {
        writeDelay.restart();
    }

    // Also on every config reload, so a change to contents() lands at once.
    Component.onCompleted: writeDelay.restart()

    Connections {
        target: Settings
        function onBlurStrengthChanged() {
            writeDelay.restart();
        }
        function onBlurChanged() {
            writeDelay.restart();
        }
        function onBlurXrayChanged() {
            writeDelay.restart();
        }
    }

    // Dragging the slider changes the value per step; write once it settles.
    Timer {
        id: writeDelay
        interval: 300
        onTriggered: mkdir.running = true
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.stateDir]
        onExited: output.setText(root.contents(Settings.blurStrength, Settings.blur, Settings.blurXray))
    }

    FileView {
        id: output
        path: root.path
        atomicWrites: true
        printErrors: false
    }

    FileView {
        path: root.niriConfig
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // config.kdl may spell the path with ~ (niri expands it).
        onLoaded: root.included = text().includes(root.path) || text().includes(root.path.replace(Quickshell.env("HOME"), "~"))
    }
}
