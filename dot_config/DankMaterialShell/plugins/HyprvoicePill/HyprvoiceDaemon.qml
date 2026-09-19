pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins
import qs.Widgets

// A status pill for hyprvoice dictation, in the spirit of OpenHyprWhisper's.
//
// hyprvoice has no event stream - its socket answers one command per
// connection - so nothing here polls while you are not dictating. The niri
// bind calls `dms ipc call hyprvoice toggle` instead of `hyprvoice toggle`
// directly, which both starts the dictation and wakes the poller. Toggling
// from a terminal still dictates; it just does not draw the pill.
PluginComponent {
    id: root

    // hyprvoice's own pipeline states, plus "done", which is ours: the daemon
    // drops straight back to idle after injecting and the pill wants a beat to
    // say so before it leaves.
    property string phase: "idle"
    property bool watching: false
    property double startedAt: 0
    property int elapsedMs: 0
    property var levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    // Must match the bars= in hyprvoice-pill-cava (components/hyprvoice.nix).
    readonly property int barCount: 12
    // hyprvoice's status names describe its pipeline, not what you are doing:
    // it sets "transcribing" as soon as the recorder starts streaming frames,
    // and "injecting" the moment you stop - before whisper has run a single
    // token. So listening is recording+transcribing, and the wait after you
    // stop talking is what this pill calls transcribing.
    readonly property bool listening: phase === "recording" || phase === "transcribing"
    readonly property bool busy: phase === "processing" || phase === "injecting"

    function zeroLevels() {
        var a = [];
        for (var i = 0; i < root.barCount; i++)
            a.push(0);
        return a;
    }

    function applyStatus(line) {
        var m = /status=([a-z]+)/.exec(line);
        if (!m)
            return;
        var next = m[1];
        if (next === root.phase)
            return;

        if (next === "idle") {
            // Only a session that actually ran earns the "Done" beat; the first
            // poll after a toggle can legitimately still read idle.
            if (root.phase !== "idle" && root.phase !== "done") {
                root.phase = "done";
                doneTimer.restart();
            }
            return;
        }

        if (root.phase === "idle" || root.phase === "done") {
            root.startedAt = Date.now();
            root.elapsedMs = 0;
        }
        doneTimer.stop();
        root.phase = next;
    }

    function elapsedText() {
        var total = Math.floor(root.elapsedMs / 1000);
        var mins = Math.floor(total / 60);
        var secs = total % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    // ---- control ----
    IpcHandler {
        target: "hyprvoice"

        function toggle(): string {
            toggleProc.running = true;
            root.watching = true;
            return "ok";
        }

        function cancel(): string {
            cancelProc.running = true;
            return "ok";
        }
    }

    Process {
        id: toggleProc

        command: ["hyprvoice", "toggle"]
        running: false
    }

    Process {
        id: cancelProc

        command: ["hyprvoice", "cancel"]
        running: false
    }

    // ---- state ----
    Process {
        id: statusPoll

        running: root.watching
        command: ["sh", "-c", "while :; do hyprvoice status 2>/dev/null || echo 'STATUS status=idle'; sleep 0.1; done"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.applyStatus(data)
        }
    }

    Timer {
        id: doneTimer

        interval: 900
        onTriggered: {
            root.phase = "idle";
            root.watching = false;
            root.levels = root.zeroLevels();
        }
    }

    // A toggle that never produces a session - daemon down, mic missing - would
    // otherwise leave the poller running forever.
    Timer {
        id: watchdog

        running: root.watching && root.phase === "idle"
        interval: 3000
        onTriggered: root.watching = false
    }

    Timer {
        id: ticker

        running: root.listening
        interval: 100
        repeat: true
        onTriggered: root.elapsedMs = Date.now() - root.startedAt
    }

    // ---- waveform ----
    // A second PipeWire capture of the same source hyprvoice is recording from.
    // Two readers on one mic is fine; this one only exists while recording.
    Process {
        id: cava

        running: root.listening
        command: ["hyprvoice-pill-cava"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!root.listening || data.length === 0)
                    return;
                var parts = data.split(";");
                if (parts.length < root.barCount)
                    return;
                var out = [];
                for (var i = 0; i < root.barCount; i++)
                    out.push(parseInt(parts[i], 10) || 0);
                root.levels = out;
            }
        }

        onRunningChanged: {
            if (!running)
                root.levels = root.zeroLevels();
        }
    }

    // ---- pill ----
    LazyLoader {
        active: root.phase !== "idle"

        PanelWindow {
            id: pill

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "dms:plugins:hyprvoice-pill"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.bottom: true
            // Clears the DankBar and dock at the bottom edge.
            margins.bottom: 96

            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            // The same blur path DMS uses for its own popouts: a
            // BackgroundEffect region published to the compositor, gated on
            // BlurService, so it follows the shell's blur setting and
            // compositor support rather than inventing a second one.
            WindowBlur {
                targetWindow: pill
                blurWidth: card.implicitWidth
                blurHeight: card.implicitHeight
                blurRadius: card.implicitHeight / 2
            }

            Rectangle {
                id: card

                implicitWidth: layout.implicitWidth + Theme.spacingL * 2
                implicitHeight: Math.round(Theme.fontSizeLarge * 2.6)
                radius: height / 2
                // hostSurface at popupTransparency is what DMS popouts paint,
                // so this tracks the surface opacity slider.
                color: Theme.readableSurface
                border.width: BlurService.borderWidth
                // Off unless the blur border setting is on, and then its color,
                // role and opacity - the same outline as every other DMS layer.
                border.color: BlurService.borderColor
                opacity: 0

                Component.onCompleted: opacity = 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Row {
                    id: layout

                    anchors.centerIn: parent
                    spacing: Theme.spacingM

                    // Recording dot, pulsing; a check when the text lands.
                    Item {
                        width: Theme.fontSizeLarge
                        height: Theme.fontSizeLarge
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            visible: !(root.phase === "done")
                            width: root.listening ? Theme.fontSizeLarge * 0.7 : Theme.fontSizeLarge * 0.5
                            height: width
                            radius: width / 2
                            color: root.listening ? Theme.error : Theme.primary

                            SequentialAnimation on opacity {
                                running: root.listening
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.35
                                    duration: 620
                                    easing.type: Easing.InOutSine
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 620
                                    easing.type: Easing.InOutSine
                                }
                            }

                            // A spinner while hyprvoice is off doing the work.
                            RotationAnimation on rotation {
                                running: root.busy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        DankIcon {
                            anchors.centerIn: parent
                            visible: root.phase === "done"
                            name: "check"
                            size: Theme.fontSizeLarge
                            color: Theme.primary
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            switch (root.phase) {
                            case "recording":
                                return "Recording...";
                            case "transcribing":
                                return "Recording...";
                            case "processing":
                                return "Polishing...";
                            case "injecting":
                                return "Transcribing...";
                            case "done":
                                return "Done";
                            }
                            return "";
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }

                    // Live mic level. Bars sit at a floor height so the pill
                    // keeps its shape between words instead of collapsing.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.listening
                        spacing: 3

                        Repeater {
                            model: root.barCount

                            Rectangle {
                                required property int index

                                readonly property real level: Math.min(1, (root.levels[index] || 0) / 100)

                                width: 3
                                radius: 1.5
                                height: 3 + level * (Theme.fontSizeLarge * 1.4)
                                color: Theme.primary
                                opacity: 0.55 + level * 0.45
                                anchors.verticalCenter: parent.verticalCenter

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 70
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.listening
                        text: root.elapsedText()
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
