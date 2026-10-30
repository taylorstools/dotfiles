pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// A status pill for whisrs dictation, ported from Taylor's old WhisrsPill
// plugin, drawn with this shell's surface, blur
// and outline instead of whisrs's own overlay (overlay = false in its config).
//
// whisrs fires its [hooks] on_record_start / on_record_stop on every recording
// state change, whatever caused it: its own evdev hotkey, a niri bind, the CLI
// or the tray. The hooks call `qs ipc call whisrs started|stopped`, so the pill
// appears the instant recording starts and nothing here polls while you are
// not dictating. The status poll only runs from a start until whisrs is idle
// again, to see the transcribing tail that the hooks do not report.
Scope {
    id: root

    // whisrs's own states, plus "done", which is ours: the daemon drops
    // straight back to idle once the text is typed and the pill wants a beat
    // to say so before it leaves.
    property string phase: "idle"
    property bool watching: false
    property double startedAt: 0
    property int elapsedMs: 0
    property var levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    // Must match the bars= in whisrs-pill-cava (nixos components/whisrs.nix).
    readonly property int barCount: 12

    // whisrs's state names mean what they say: "recording" is you talking,
    // "transcribing" is the flush after you stop. local-whisper streams, so
    // most of the text has already been typed by then.
    readonly property bool listening: phase === "recording"
    readonly property bool busy: phase === "transcribing"

    function zeroLevels() {
        const a = [];
        for (let i = 0; i < barCount; i++)
            a.push(0);
        return a;
    }

    function beginSession() {
        if (phase !== "recording") {
            startedAt = Date.now();
            elapsedMs = 0;
        }
        doneTimer.stop();
        phase = "recording";
        watching = true;
    }

    function applyStatus(line) {
        const m = /\b(idle|recording|transcribing|synthesizing|speaking)\b/.exec(line);
        if (!m)
            return;
        let next = m[1];

        // Read-aloud is whisrs talking, not you dictating: no pill for it.
        if (next === "synthesizing" || next === "speaking")
            next = "idle";
        if (next === phase)
            return;

        if (next === "idle") {
            // Only a session that actually ran earns the "Done" beat.
            if (phase === "recording" || phase === "transcribing") {
                phase = "done";
                doneTimer.restart();
            }
            return;
        }

        if (next === "recording") {
            beginSession();
            return;
        }

        doneTimer.stop();
        phase = next;
    }

    function elapsedText() {
        const total = Math.floor(elapsedMs / 1000);
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    IpcHandler {
        target: "whisrs"

        // on_record_start
        function started(): string {
            root.beginSession();
            return "ok";
        }

        // on_record_stop: fires at the first non-recording state, so flip to
        // transcribing straight away instead of waiting a poll for it.
        function stopped(): string {
            if (root.phase === "recording")
                root.phase = "transcribing";
            root.watching = true;
            return "ok";
        }
    }

    Process {
        running: root.watching
        // `whisrs status` prints a bare state word when stdout is not a TTY.
        command: ["sh", "-c", "while :; do whisrs status 2>/dev/null || echo idle; sleep 0.1; done"]

        stdout: SplitParser {
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

    // A stop hook with no session behind it (daemon restarted mid-recording,
    // say) would otherwise leave the poller running forever.
    Timer {
        running: root.watching && root.phase === "idle"
        interval: 3000
        onTriggered: root.watching = false
    }

    Timer {
        running: root.listening
        interval: 100
        repeat: true
        onTriggered: root.elapsedMs = Date.now() - root.startedAt
    }

    // The waveform: a second PipeWire capture of the same default source
    // whisrs records from. Two readers on one mic is fine; this one only
    // exists while recording.
    Process {
        running: root.listening
        command: ["whisrs-pill-cava"]

        stdout: SplitParser {
            onRead: data => {
                if (!root.listening || data.length === 0)
                    return;
                const parts = data.split(";");
                if (parts.length < root.barCount)
                    return;
                const out = [];
                for (let i = 0; i < root.barCount; i++)
                    out.push(parseInt(parts[i], 10) || 0);
                root.levels = out;
            }
        }

        onRunningChanged: {
            if (!running)
                root.levels = root.zeroLevels();
        }
    }

    LazyLoader {
        active: root.phase !== "idle"

        PanelWindow {
            id: pill

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qstest:whisrs"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.bottom: true
            // Clears the bar and the OSD at the bottom edge.
            margins.bottom: 96

            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            // Clicks go through to whatever is underneath.
            mask: Region {}

            Item {
                Region {
                    id: blurRegion
                    width: card.width
                    height: card.height
                }
            }

            function applyBlur() {
                // Region.radius only exists in newer Quickshell builds.
                if ("radius" in blurRegion)
                    blurRegion.radius = card.radius;
                if (pill.BackgroundEffect !== undefined)
                    pill.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
            }

            Component.onCompleted: applyBlur()

            Connections {
                target: Settings
                function onBlurChanged() {
                    pill.applyBlur();
                }
            }

            Rectangle {
                id: card

                implicitWidth: layout.implicitWidth + Theme.spacingL * 2
                implicitHeight: Math.round(Theme.fontSizeLarge * 2.6)
                radius: height / 2
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.blurBorder
                opacity: 0

                Component.onCompleted: opacity = 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    id: layout

                    anchors.centerIn: parent
                    spacing: Theme.spacingM

                    // Recording dot, pulsing; a spinner while transcribing; a
                    // check when the text lands.
                    Item {
                        width: Theme.fontSizeLarge
                        height: Theme.fontSizeLarge
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            visible: root.phase !== "done"
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

                            RotationAnimation on rotation {
                                running: root.busy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        MaterialIcon {
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
                                return "Transcribing...";
                            case "done":
                                return "Done";
                            }
                            return "";
                        }
                        font.pixelSize: Theme.fontSizeMedium
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
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
