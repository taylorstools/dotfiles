import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// A Win+R-style runner, ported from ~/scripts/runner.sh. The prompt is the
// folder you're in; typing fuzzy-finds everything below it (its own entries
// first), ranked by `fzf --filter` so it matches what the script did.
//   qs ipc -p <this folder> call runner toggle      (or ./run.sh runner)
//
//   Up/Down         move through the entries
//   Right / Tab     step into the highlighted folder, or put the highlighted
//                   file's name in the field
//   Backspace       on an empty field, go up one folder
//   typing /, ~, .. jump there directly (a pasted full path works too)
//   Enter           open: folders in Thunar, text files in xed or VSCodium
//                   (asks), anything else with xdg-open; with nothing
//                   highlighted, open what you typed as a path or URL
//   Alt+Enter       run: what you typed if it starts with a command on PATH,
//                   else the highlighted program or script, else what you
//                   typed as a shell command
//   Ctrl+F          switch between everything below and this folder only
//   Ctrl+A          back to / with nothing typed
//   Ctrl+C          copy the highlighted path (or what you typed) and close
//   Esc             close
//
// Listing, the text-file check and the Alt+Enter rules are in
// runner-helper.sh, kept close to the script's own code.
Scope {
    id: root

    property bool shown: false
    property string dir: home + "/"
    // "tree" (everything below) or "flat" (this folder only)
    property string mode: "tree"
    // [{ path, display }] as fzf ranked them; folders end in /.
    property var results: []
    property bool loading: false
    // Shown in place of the key hints until the field changes.
    property string message: ""
    // The text file waiting for "xed or VSCodium?".
    property string choosingFile: ""
    property int choiceIndex: 0

    // Each reload writes its own list file, so a slow fd from the folder you
    // just left can't append to the new folder's list.
    property int generation: 0
    readonly property string listFile: runtimeDir + "/qstest-runner-" + generation + ".tsv"

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string helper: Quickshell.shellDir + "/Runner/runner-helper.sh"
    readonly property string query: input.text
    readonly property var current: results[list.currentIndex] ?? null

    readonly property string hints: mode === "flat" ? "this folder only · ^F search subfolders too · → into · ⌫ up · alt-⏎ run" : "→ into · ⌫ up · ^F this folder only · alt-⏎ run · ^A clear · ^C copy"

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            window.screen = target;
        mode = "tree";
        choosingFile = "";
        shown = true;
        nav(home + "/", "");
    }

    function hide() {
        shown = false;
        choosingFile = "";
        lister.running = false;
        belowLister.running = false;
        Quickshell.execDetached(["rm", "-f", listFile]);
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    function isUrl(text) {
        return /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(text);
    }

    // Typed text against the current folder: /abs, ~, ~/x, or relative.
    function resolve(text) {
        if (text.startsWith("/"))
            return text;
        if (text === "~")
            return home + "/";
        if (text.startsWith("~/"))
            return home + "/" + text.slice(2);
        return dir + text;
    }

    function parentOf(path) {
        const trimmed = path.endsWith("/") ? path.slice(0, -1) : path;
        const parent = trimmed.slice(0, trimmed.lastIndexOf("/") + 1);
        return parent || "/";
    }

    function baseName(path) {
        const trimmed = path.endsWith("/") ? path.slice(0, -1) : path;
        return trimmed.slice(trimmed.lastIndexOf("/") + 1);
    }

    // Show folder `folder` (with trailing slash) with `text` in the field.
    function nav(folder, text) {
        dir = folder;
        input.text = text;
        input.cursorPosition = text.length;
        reload();
    }

    function reload() {
        lister.running = false;
        belowLister.running = false;
        Quickshell.execDetached(["rm", "-f", listFile]);
        generation++;
        results = [];
        loading = true;
        lister.command = ["sh", "-c", 'exec bash "$1" list-dir "$2" > "$3"', "sh", helper, dir, listFile];
        lister.running = true;
    }

    function refilter() {
        if (filter.running) {
            filter.again = true;
            return;
        }
        filter.command = ["sh", "-c", 'fzf --filter "$1" --scheme path --delimiter "\t" --nth 2 < "$2" 2>/dev/null | head -n 300', "sh", query, listFile];
        filter.running = true;
    }

    // Right/Tab: into the highlighted folder, or complete the file's name.
    function complete() {
        if (!current)
            return false;
        if (current.path.endsWith("/"))
            nav(current.path, "");
        else
            nav(parentOf(current.path), baseName(current.path));
        return true;
    }

    function up() {
        if (dir !== "/")
            nav(parentOf(dir), "");
    }

    function toggleMode() {
        mode = mode === "flat" ? "tree" : "flat";
        reload();
    }

    // Enter: the highlighted entry, else what was typed (a URL opens right away).
    function enter() {
        if (current) {
            open(current.path);
        } else if (query === "") {
            return;
        } else if (isUrl(query)) {
            Quickshell.execDetached(["xdg-open", query]);
            hide();
        } else {
            open(resolve(query));
        }
    }

    function open(path) {
        kind.path = path;
        kind.command = ["bash", helper, "kind", path];
        kind.running = true;
    }

    function openWith(editor) {
        Quickshell.execDetached([editor, choosingFile]);
        hide();
    }

    // Esc from the editor question: back to the runner, on that file.
    function cancelChoice() {
        const file = choosingFile;
        choosingFile = "";
        nav(parentOf(file), baseName(file));
    }

    function run() {
        if (query === "" && !current)
            return;
        Quickshell.execDetached(["bash", helper, "run", dir, query, current ? current.path : ""]);
        hide();
    }

    function copy() {
        const text = current ? current.path : resolve(query);
        Quickshell.execDetached(["wl-copy", "--", text]);
        hide();
    }

    // Bold the characters that match, the way fzf highlights them (greedy,
    // smart case: case-insensitive unless you type a capital).
    function highlight(display) {
        const escape = c => c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c;
        const needle = query.replace(/\s+/g, "");
        const caseSensitive = needle !== needle.toLowerCase();
        let out = "";
        let n = 0;
        for (const c of display) {
            const a = caseSensitive ? c : c.toLowerCase();
            const b = caseSensitive ? needle[n] : (needle[n] ?? "").toLowerCase();
            if (n < needle.length && a === b) {
                out += "<font color=\"" + Theme.primary + "\"><b>" + escape(c) + "</b></font>";
                n++;
            } else {
                out += escape(c);
            }
        }
        return out;
    }

    IpcHandler {
        target: "runner"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
    }

    Process {
        id: lister

        property int startedFor: 0

        onStarted: startedFor = root.generation
        onExited: {
            if (startedFor !== root.generation)
                return;
            root.refilter();
            if (root.mode === "tree") {
                belowLister.command = ["sh", "-c", 'exec bash "$1" list-below "$2" >> "$3"', "sh", root.helper, root.dir, root.listFile];
                belowLister.running = true;
            } else {
                root.loading = false;
            }
        }
    }

    Process {
        id: belowLister

        property int startedFor: 0

        onStarted: startedFor = root.generation
        onExited: {
            if (startedFor !== root.generation)
                return;
            root.loading = false;
            root.refilter();
        }
    }

    Process {
        id: filter

        property bool again: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.results = text.split("\n").filter(l => l).map(l => {
                    const tab = l.indexOf("\t");
                    return {
                        "path": l.slice(0, tab),
                        "display": l.slice(tab + 1)
                    };
                });
                list.currentIndex = 0;
            }
        }
        onExited: {
            if (again) {
                again = false;
                root.refilter();
            }
        }
    }

    // A typed path: if the part before the last slash is a folder, move it
    // into the prompt and keep only what's after the slash.
    Process {
        id: dirCheck

        property string forText
        property string rest

        stdout: StdioCollector {
            onStreamFinished: {
                if (text !== "" && root.query === dirCheck.forText)
                    root.nav(text, dirCheck.rest);
            }
        }
    }

    Process {
        id: kind

        property string path

        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                if (result === "missing") {
                    root.message = "Nothing matches: " + root.query + " (alt-⏎ to run it)";
                    return;
                }
                if (result === "editor-choice") {
                    root.choosingFile = kind.path;
                    root.choiceIndex = 0;
                    return;
                }
                const opener = result === "dir" ? "thunar" : (result === "editor" ? "xed" : "xdg-open");
                Quickshell.execDetached([opener, kind.path]);
                root.hide();
            }
        }
    }

    // Keystrokes come quickly; fzf reruns once they settle.
    Timer {
        id: filterDelay
        interval: 40
        onTriggered: root.refilter()
    }


    // Keeps the window up until the closing animation is done.
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

        WlrLayershell.namespace: "qstest:runner"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                input.forceActiveFocus();
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

        // Re-apply when blur is switched in the settings window.
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

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: panel

            // Fades and grows in from 95%; Settings > Appearance sets the speed.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

            readonly property real rowHeight: 34
            readonly property real pad: Theme.spacingS

            anchors.centerIn: parent
            width: Config.runnerWidth
            height: pad * 4 + field.height + rowHeight * Config.runnerVisibleRows + hintText.height
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallow clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: field

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                height: 44
                radius: Theme.cornerRadius - panel.pad / 2
                color: Theme.overlay(Theme.surfaceContainerHigh, 0.9)

                MaterialIcon {
                    id: promptIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.choosingFile !== "" ? "edit_document" : "terminal"
                    size: 20
                    color: Theme.primary
                }

                // The folder you're in; long paths lose their start, not their end.
                StyledText {
                    id: prompt
                    anchors.left: promptIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, field.width * 0.55)
                    text: root.choosingFile !== "" ? "Open " + root.baseName(root.choosingFile) + " with:" : root.dir
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideLeft
                }

                TextInput {
                    id: input

                    anchors.left: prompt.right
                    anchors.right: busy.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.choosingFile === ""
                    color: Theme.surfaceText
                    selectionColor: Theme.primarySelected
                    selectedTextColor: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.weight: Theme.fontWeight
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    focus: true

                    onTextChanged: {
                        root.message = "";
                        if (text.includes("/") && !root.isUrl(text)) {
                            const target = root.resolve(text);
                            const slash = target.lastIndexOf("/");
                            dirCheck.forText = text;
                            dirCheck.rest = target.slice(slash + 1);
                            dirCheck.command = ["bash", root.helper, "dir", target.slice(0, slash + 1)];
                            dirCheck.running = true;
                        }
                        filterDelay.restart();
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const count = list.count;
                        if (root.choosingFile !== "") {
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.cancelChoice();
                                break;
                            case Qt.Key_Up:
                            case Qt.Key_Down:
                                root.choiceIndex = 1 - root.choiceIndex;
                                break;
                            case Qt.Key_1:
                                root.openWith("xed");
                                break;
                            case Qt.Key_2:
                                root.openWith("codium");
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                root.openWith(root.choiceIndex === 0 ? "xed" : "codium");
                                break;
                            }
                            event.accepted = true;
                            return;
                        }
                        if (ctrl && event.key === Qt.Key_F) {
                            root.toggleMode();
                        } else if (ctrl && event.key === Qt.Key_A) {
                            root.nav("/", "");
                        } else if (ctrl && event.key === Qt.Key_C) {
                            root.copy();
                        } else {
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.hide();
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                if (event.modifiers & Qt.AltModifier)
                                    root.run();
                                else
                                    root.enter();
                                break;
                            case Qt.Key_Down:
                                if (count > 0)
                                    list.currentIndex = (list.currentIndex + 1) % count;
                                break;
                            case Qt.Key_Up:
                                if (count > 0)
                                    list.currentIndex = (list.currentIndex - 1 + count) % count;
                                break;
                            case Qt.Key_Tab:
                                root.complete();
                                break;
                            case Qt.Key_Right:
                                // Only at the end of the text; elsewhere it moves the cursor.
                                if (cursorPosition < text.length || !root.complete())
                                    return;
                                break;
                            case Qt.Key_Backspace:
                                if (text !== "")
                                    return;
                                root.up();
                                break;
                            default:
                                return;
                            }
                        }
                        event.accepted = true;
                    }
                }

                MaterialIcon {
                    id: busy
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.mode === "flat" ? "folder" : "account_tree"
                    size: 18
                    color: Theme.surfaceVariantText
                    opacity: root.loading ? 0.4 : 1

                    SequentialAnimation on opacity {
                        running: root.loading
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.3
                            duration: 400
                        }
                        NumberAnimation {
                            to: 1
                            duration: 400
                        }
                    }
                }
            }

            ListView {
                id: list

                anchors.top: field.bottom
                anchors.topMargin: panel.pad
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                height: panel.rowHeight * Config.runnerVisibleRows
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                visible: root.choosingFile === ""
                model: root.results

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property bool isDir: modelData.path.endsWith("/")

                    width: ListView.view.width
                    height: panel.rowHeight
                    radius: Theme.cornerRadius - panel.pad / 2
                    color: selected ? Theme.withAlpha(Theme.primary, 0.2) : (rowMouse.containsMouse ? Theme.widgetHover : "transparent")

                    MaterialIcon {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.isDir ? "folder" : "draft"
                        size: 18
                        filled: row.isDir
                        color: row.isDir ? Theme.primary : Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.highlight(row.modelData.display)
                        textFormat: Text.StyledText
                        color: row.selected ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.85)
                        font.pixelSize: Theme.fontSizeSmall + 1
                        elide: Text.ElideLeft
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            list.currentIndex = row.index;
                            root.enter();
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0 && !root.loading
                    text: root.query === "" ? "This folder is empty" : "Nothing matches (alt-⏎ runs it)"
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }

            // "xed or VSCodium?" for text files, like the script's second fzf.
            Column {
                anchors.top: field.bottom
                anchors.topMargin: panel.pad
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                visible: root.choosingFile !== ""
                spacing: 2

                Repeater {
                    model: ["xed", "VSCodium"]

                    delegate: Rectangle {
                        id: choice

                        required property string modelData
                        required property int index

                        width: parent.width
                        height: panel.rowHeight
                        radius: Theme.cornerRadius - panel.pad / 2
                        color: root.choiceIndex === index ? Theme.withAlpha(Theme.primary, 0.2) : (choiceMouse.containsMouse ? Theme.widgetHover : "transparent")

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: (choice.index + 1) + "   " + choice.modelData
                        }

                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openWith(choice.index === 0 ? "xed" : "codium")
                        }
                    }
                }
            }

            StyledText {
                id: hintText
                anchors.bottom: parent.bottom
                anchors.bottomMargin: panel.pad
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - panel.pad * 4
                horizontalAlignment: Text.AlignHCenter
                text: root.choosingFile !== "" ? "⏎ open · 1/2 pick · esc back" : (root.message !== "" ? root.message : root.hints)
                color: root.message !== "" ? Theme.error : Theme.outline
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }
    }
}
