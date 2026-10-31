import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Volume / brightness / mic OSD at the bottom center above the bar (your old
// osdPosition). It reacts to the levels changing, however they changed: the
// audio/brightness IPC, wpctl, another app. It stays quiet while the control
// center is open, since its sliders already show the level, and for a moment
// after startup or a device switch, when levels arrive without anyone
// changing them.
//
// Scripts show toasts in the same pill, an icon and a line of text. They
// aren't notifications, so they never reach the notification tray:
//   qs ipc call toast info "Refresh rate set to 120Hz"
//   qs ipc call toast warn "..."     qs ipc call toast error "..."
//   qs ipc call toast icon coffee "PC will now stay awake"   (any Material icon)
Scope {
    id: root

    // "volume", "brightness", "mic" or "toast"
    property string kind: ""
    property bool shown: false
    property bool settled: false

    readonly property var sinkAudio: Audio.sink?.audio ?? null
    readonly property var sourceAudio: Audio.source?.audio ?? null

    property string toastText: ""
    property string toastIcon: ""
    property bool toastError: false

    readonly property bool muted: {
        if (kind === "toast")
            return false;
        return kind === "mic" ? (sourceAudio?.muted ?? false) : (sinkAudio?.muted ?? false);
    }
    readonly property real level: kind === "brightness" ? Brightness.value : (sinkAudio?.volume ?? 0)
    readonly property string icon: {
        if (kind === "toast")
            return toastIcon;
        if (kind === "brightness")
            return level < 0.5 ? "brightness_low" : "light_mode";
        if (kind === "mic")
            return muted ? "mic_off" : "mic";
        if (muted)
            return "volume_off";
        if (level === 0)
            return "volume_mute";
        return level <= 0.33 ? "volume_down" : "volume_up";
    }

    // Scripts that change levels behind the scenes (hypridle restoring the
    // brightness it dimmed) hide the OSD for a moment:
    //   qs ipc call osd suppress 1500
    property double suppressedUntil: 0

    function show(which) {
        if (!settled || Popouts.controlCenterScreen !== null || Date.now() < suppressedUntil)
            return;
        kind = which;
        shown = true;
        hideTimer.restart();
    }

    // Unlike the level OSD, always shown: nothing else on screen says it.
    function toast(icon, text, error) {
        toastIcon = icon;
        toastText = text;
        toastError = error;
        kind = "toast";
        shown = true;
        hideTimer.restart();
    }

    function unsettle() {
        settled = false;
        settleTimer.restart();
    }

    onSinkAudioChanged: unsettle()
    onSourceAudioChanged: unsettle()
    Component.onCompleted: unsettle()

    IpcHandler {
        target: "osd"

        function suppress(ms: int): void {
            root.suppressedUntil = Date.now() + Math.max(0, ms);
            root.shown = false;
        }
    }

    IpcHandler {
        target: "toast"

        function info(text: string): void {
            root.toast("info", text, false);
        }
        function warn(text: string): void {
            root.toast("warning", text, false);
        }
        function error(text: string): void {
            root.toast("error", text, true);
        }
        function icon(name: string, text: string): void {
            root.toast(name, text, false);
        }
    }

    Timer {
        id: settleTimer
        interval: 1000
        onTriggered: root.settled = true
    }

    Timer {
        id: hideTimer
        interval: root.kind === "toast" ? Config.toastDuration : 1500
        onTriggered: root.shown = false
    }

    Connections {
        target: root.sinkAudio
        function onVolumeChanged() {
            root.show("volume");
        }
        function onMutedChanged() {
            root.show("volume");
        }
    }

    Connections {
        target: root.sourceAudio
        function onMutedChanged() {
            root.show("mic");
        }
    }

    Connections {
        target: Brightness
        function onValueChanged() {
            root.show("brightness");
        }
    }

    PanelWindow {
        id: window

        screen: {
            const screens = Array.from(Quickshell.screens);
            return screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        visible: pill.opacity > 0
        anchors.bottom: true
        margins.bottom: Theme.spacingL
        implicitWidth: pill.width
        implicitHeight: pill.height
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        // Clicks go straight through to whatever is underneath.
        mask: Region {}

        WlrLayershell.namespace: "qstest:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Compositor blur behind the OSD pill (needs a recent Quickshell).
        Item {
            Region {
                id: blurRegion
                x: pill.x
                y: pill.y
                width: pill.width
                height: pill.height
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = pill.radius;
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
        }

        Component.onCompleted: applyBlur()
        onVisibleChanged: applyBlur()

        Connections {
            target: Settings
            function onBlurChanged() {
                window.applyBlur();
            }
        }

        Rectangle {
            id: pill

            // Sized to whole screen pixels, or the window clips the right edge.
            width: {
                if (root.kind === "toast")
                    return Theme.wholeSize(toastRow.implicitWidth + 36);
                return root.kind === "mic" ? Theme.wholeSize(micRow.implicitWidth + 36) : Config.osdWidth;
            }
            height: 48
            radius: height / 2
            color: Theme.popupBackground
            border.width: 1
            border.color: (root.kind === "mic" && root.muted) || (root.kind === "toast" && root.toastError) ? Theme.error : Theme.blurBorder
            opacity: root.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animDuration
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12
                visible: root.kind !== "mic" && root.kind !== "toast"

                MaterialIcon {
                    name: root.icon
                    size: 22
                    filled: true
                    color: root.muted ? Theme.outline : Theme.primary
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    radius: 4.5
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.level))
                        height: parent.height
                        radius: 4.5
                        color: root.muted ? Theme.outline : Theme.primary

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.animShort
                            }
                        }
                    }
                }

                StyledText {
                    Layout.preferredWidth: 42
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "Muted" : Math.round(root.level * 100) + "%"
                    color: Theme.surfaceVariantText
                    font.pixelSize: 13
                }
            }

            Row {
                id: micRow
                anchors.centerIn: parent
                spacing: 12
                visible: root.kind === "mic"

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.icon
                    size: 22
                    filled: true
                    color: root.muted ? Theme.error : Theme.primary
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.muted ? "Microphone muted" : "Microphone on"
                    font.pixelSize: 13
                }
            }

            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 12
                visible: root.kind === "toast"

                MaterialIcon {
                    id: toastIconItem
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.toastIcon
                    size: 22
                    filled: true
                    color: root.toastError ? Theme.error : Theme.primary
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Config.toastMaxWidth - 36 - toastIconItem.width - parent.spacing)
                    text: root.toastText
                    elide: Text.ElideRight
                    font.pixelSize: 13
                }
            }
        }
    }
}
