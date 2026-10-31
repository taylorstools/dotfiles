import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Snipping tool, the replacement for scripts/snipping-tool.sh and its yad
// dialogs. The panel picks a mode (region, window, screen) and a delay; the
// screenshot goes to the clipboard and a notification says so, whose Save
// button (or a click on it) opens a save dialog, suggesting
// ~/Pictures/Screenshots/Screenshot_<time>.png. Keys in the panel: R W S
// for the mode, 0-5 for the delay, Enter to take it, Esc to cancel.
// Region freezes the screens first: a still of each one covers it while
// slurp runs, and grim captures that still.
//   qs ipc call snip open      the panel (Print)
//   qs ipc call snip region    straight to region select (Ctrl+Print)
// snip-helper.sh does the capture itself (grim, slurp, niri).
Scope {
    id: root

    property bool shown: false
    property string mode: "Region"
    property int delay: 0

    readonly property string helper: Quickshell.shellDir + "/SnippingTool/snip-helper.sh"
    readonly property string shotDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/snipping-tool"
    readonly property string saveDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
    // Screenshots whose Save was pressed while another save dialog was up.
    property var saveQueue: []
    property var saving: null
    // A region select is running (one slurp at a time).
    property bool selecting: false

    function show() {
        if (!motion.mapped) {
            const screens = Array.from(Quickshell.screens);
            window.screen = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        shown = true;
    }

    // Close the panel, then wait out its fade (so it isn't in the shot) and
    // the delay before capturing.
    function take(withMode, withDelay) {
        const fade = motion.mapped ? Theme.animDuration + 150 : 0;
        shown = false;
        captureDelay.mode = withMode;
        captureDelay.interval = withDelay * 1000 + fade;
        captureDelay.restart();
    }

    function capture(withMode) {
        if (withMode === "Region") {
            if (selecting)
                return;
            selecting = true;
        }
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        // Its own file per screenshot, so a second one taken while this
        // notification is still up doesn't replace the image its Save saves.
        const file = shotDir + "/screenshot-" + Date.now() + ".png";
        shotComponent.createObject(root, {
            file: file,
            stamp: stamp,
            mode: withMode
        });
    }

    // symbol: the Material Symbol on the notification (NotificationCard).
    function notifyError(symbol, title, body) {
        Quickshell.execDetached(["notify-send", "--app-name=Snipping Tool", "--urgency=critical", "--hint=string:x-material-symbol:" + symbol, title, body]);
    }

    function askSave(shot) {
        if (saving) {
            saveQueue = saveQueue.concat([shot]);
            return;
        }
        // GTK's file chooser aborts the whole shell without its GSettings
        // schemas, which quickshell.nix's wrapper around qs adds.
        if (!(Quickshell.env("XDG_DATA_DIRS") ?? "").includes("/gsettings-schemas/gtk+3")) {
            notifyError("save", "Couldn't save screenshot", "No file chooser: qs is missing GTK's schemas (quickshell.nix)");
            shot.finish();
            return;
        }
        saving = shot;
        // An open flyout (the notification centre, where Save may have been
        // clicked) sits above windows and holds the keyboard.
        Popouts.closeFlyouts();
        Quickshell.execDetached(["mkdir", "-p", saveDir]);
        saveDialog.currentFolder = "file://" + saveDir;
        saveDialog.selectedFile = "file://" + saveDir + "/Screenshot_" + shot.stamp + ".png";
        saveDialog.open();
    }

    function saveDone() {
        const shot = saving;
        saving = null;
        if (shot)
            shot.finish();
        if (saveQueue.length > 0) {
            const next = saveQueue[0];
            saveQueue = saveQueue.slice(1);
            askSave(next);
        }
    }

    IpcHandler {
        target: "snip"

        function open(): void {
            root.show();
        }
        function toggle(): void {
            if (root.shown)
                root.shown = false;
            else
                root.show();
        }
        function region(): void {
            root.take("Region", 0);
        }
    }

    Timer {
        id: captureDelay
        property string mode: "Region"
        onTriggered: root.capture(mode)
    }

    // One screenshot: capture, clipboard, notification, maybe a save, then
    // the file goes.
    Component {
        id: shotComponent

        // Not drawn: a Scope, so creating one isn't a visual item with no
        // window to sit in.
        Scope {
            id: shot

            required property string file
            required property string stamp
            required property string mode

            // Region: the screens are frozen until the capture is done.
            property bool frozen: mode === "Region"
            property int frozenScreens: 0

            function finish() {
                Quickshell.execDetached(["rm", "-f", file]);
                destroy();
            }

            Component.onCompleted: {
                if (!frozen)
                    grab.running = true;
            }

            // Every screen's still is up: slurp goes on top of them.
            onFrozenScreensChanged: {
                if (frozenScreens === Quickshell.screens.length)
                    grab.running = true;
            }

            Variants {
                model: shot.frozen ? Quickshell.screens : []

                PanelWindow {
                    id: freeze

                    required property ShellScreen modelData

                    screen: modelData
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    exclusionMode: ExclusionMode.Ignore
                    // ScreencopyView only captures in a mapped window, so
                    // it's mapped clear (and isn't in the still).
                    color: still.hasContent ? "black" : "transparent"

                    WlrLayershell.namespace: "qstest:snip-freeze"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    ScreencopyView {
                        id: still
                        anchors.fill: parent
                        captureSource: freeze.modelData
                        live: false
                        // Give it a frame on screen before slurp maps over it.
                        onHasContentChanged: {
                            if (hasContent)
                                settle.start();
                        }
                    }

                    Timer {
                        id: settle
                        interval: 50
                        onTriggered: shot.frozenScreens++
                    }
                }
            }

            Process {
                id: grab
                command: ["bash", root.helper, "capture", shot.mode, shot.file]
                onExited: code => {
                    if (shot.frozen) {
                        shot.frozen = false;
                        root.selecting = false;
                    }
                    if (code === 0) {
                        // wl-copy forks and keeps serving the image.
                        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", shot.file]);
                        notify.running = true;
                    } else {
                        // 2: Esc in the region select.
                        if (code !== 2)
                            root.notifyError("broken_image", "Couldn't take screenshot", shot.mode + " capture failed");
                        shot.finish();
                    }
                }
            }

            // Waits until the notification is answered or closed. The shell
            // also runs the first action when the notification body is
            // clicked, so that saves too.
            Process {
                id: notify
                command: ["notify-send", "--app-name=Snipping Tool", "--icon=" + shot.file, "--hint=string:x-material-symbol:screenshot_region", "--action=save=Save", "--wait", "Screenshot copied to clipboard"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (text.trim() === "save")
                            root.askSave(shot);
                        else
                            shot.finish();
                    }
                }
            }
        }
    }

    // GTK's file chooser (Qt's dialog under the gtk3 platform theme); niri's
    // rules float "Save As" at 1000x650.
    FileDialog {
        id: saveDialog
        title: "Save As"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG images (*.png)"]
        onAccepted: {
            let target = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            if (!/\.png$/i.test(target))
                target += ".png";
            copy.target = target;
            copy.command = ["cp", "-f", root.saving.file, target];
            copy.running = true;
        }
        onRejected: root.saveDone()
    }

    // Only a failed save gets a notification.
    Process {
        id: copy
        property string target
        onExited: code => {
            if (code !== 0)
                root.notifyError("save", "Couldn't save screenshot", target);
            root.saveDone();
        }
    }

    PanelMotion {
        id: motion
        shown: root.shown
    }

    PanelWindow {
        id: window

        visible: motion.mapped
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "qstest:snip"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                keys.forceActiveFocus();
                applyBlur();
            }
        }

        Item {
            // Follows the panel's open/close scaling, so the blur grows with it.
            Region {
                id: blurRegion
                x: panel.x + panel.width * (1 - panel.scale) / 2
                y: panel.y + panel.height * (1 - panel.scale) / 2
                width: panel.width * panel.scale
                height: panel.height * panel.scale
            }
        }

        Connections {
            target: Settings
            function onBlurChanged() {
                window.applyBlur();
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
        }

        // Click outside the panel cancels.
        MouseArea {
            anchors.fill: parent
            onClicked: root.shown = false
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                if (!root.shown)
                    return;
                const k = event.text.toLowerCase();
                if (event.key === Qt.Key_Escape)
                    root.shown = false;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    root.take(root.mode, root.delay);
                else if (k === "r")
                    root.mode = "Region";
                else if (k === "w")
                    root.mode = "Window";
                else if (k === "s")
                    root.mode = "Screen";
                else if (k >= "0" && k <= "5" && k.length === 1)
                    root.delay = Number(k);
                else
                    return;
                event.accepted = true;
            }
        }

        Rectangle {
            id: panel

            // Fades and grows in from 95%; Settings > Appearance sets the speed.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

            readonly property real pad: Theme.spacingL

            anchors.centerIn: parent
            width: 400
            height: content.implicitHeight + pad * 2
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallows clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: panel.pad
                spacing: Theme.spacingM

                RowLayout {
                    spacing: Theme.spacingS

                    MaterialIcon {
                        name: "screenshot_region"
                        size: 22
                        color: Theme.primary
                    }

                    StyledText {
                        text: "Snipping Tool"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }

                StyledText {
                    text: "Mode"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        Repeater {
                            model: [
                                {
                                    "id": "Region",
                                    "icon": "crop"
                                },
                                {
                                    "id": "Window",
                                    "icon": "web_asset"
                                },
                                {
                                    "id": "Screen",
                                    "icon": "desktop_windows"
                                }
                            ]

                            delegate: SegmentButton {
                                required property var modelData
                                icon: modelData.icon
                                text: modelData.id
                                current: root.mode === modelData.id
                                onClicked: root.mode = modelData.id
                            }
                        }
                    }
                }

                StyledText {
                    text: "Delay"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        Repeater {
                            model: 6

                            delegate: SegmentButton {
                                required property int index
                                text: index === 0 ? "None" : index + "s"
                                current: root.delay === index
                                onClicked: root.delay = index
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.topMargin: Theme.spacingXS
                    spacing: Theme.spacingS

                    StyledText {
                        Layout.fillWidth: true
                        text: "R W S mode · 0–5 delay"
                        color: Theme.outline
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    IconButton {
                        implicitHeight: 34
                        text: "Cancel"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: root.shown = false
                    }

                    IconButton {
                        implicitHeight: 34
                        icon: "screenshot_region"
                        text: "Take"
                        restColor: Theme.primary
                        hoverColor: Qt.lighter(Theme.primary, 1.12)
                        contentColor: Theme.onPrimary
                        onClicked: root.take(root.mode, root.delay)
                    }
                }
            }
        }
    }
}
