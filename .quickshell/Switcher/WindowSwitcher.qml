import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Jump to any open window (Mod+Tab), ported from
// ~/scripts/niri_window-switcher.sh. Each window is a row with its app's icon
// and "App: window title", in layout order (workspace by workspace, columns
// left to right, top to bottom within one, floating windows last). The gutter
// shows the workspace number on its first window, bright for the workspace
// you're on, with a dot on the window you came from. One letter on each row
// is underlined: press it and that window is focused right away.
// Each window's letter comes from its app's name, preferring the start of a
// word and then the letters right after it, so the first Chrome window gets
// C, a second one H, and so on. Only when the app's name has no free letter
// left does it come from the window title, and failing that it's any free
// key, shown at the end of the row. A window keeps its letter until it closes
// (or niri restarts), however the list is ordered.
//
//   a-z, 0-9        focus the window with that letter underlined
//   Up/Down, Enter  move to a window and focus it (the cursor starts on the
//                   window you came from); Tab and Shift+Tab move too, and
//                   all of them wrap around at the ends
//   /               search: letters now type into the field to fuzzy-filter;
//                   Esc, or Backspace on an empty field, goes back to letters
//   Delete          close the highlighted window
//   Esc             close the switcher
//
// Focusing anything else (a click outside, a keybind) closes it.
//   qs ipc call switcher toggle
Scope {
    id: root

    readonly property string hintKeys: "abcdefghijklmnopqrstuvwxyz0123456789"

    property bool shown: false
    property bool searching: false
    // The window focused when the switcher opened.
    property var fromId: null
    // [{ id, appId, name, title, wsId, wsIdx, wsCurrent, key, src, pos }]
    property var entries: []
    // Window id -> letter, kept for the niri session (see the FileView).
    property var letters: ({})
    property string message: ""

    readonly property string query: input.text
    readonly property var shownEntries: {
        if (!searching || query === "")
            return entries;
        const out = [];
        for (const e of entries) {
            const hits = match(e.name + ": " + e.title, query);
            if (hits)
                out.push(Object.assign({}, e, {
                    "hits": hits
                }));
        }
        return out;
    }
    readonly property var current: shownEntries[list.currentIndex] ?? null

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            window.screen = target;
        fromId = Niri.focusedWindowId;
        searching = false;
        message = "";
        input.text = "";
        rebuild();
        shown = true;
        const start = entries.findIndex(e => e.id === fromId);
        list.currentIndex = Math.max(0, start);
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function hide() {
        shown = false;
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    function focusWindow(id) {
        if (id === undefined || id === null)
            return;
        hide();
        Niri.focusWindow(id);
    }

    // Shorter names for apps whose desktop entry name is long, by app ID
    // (lowercase). Anything not listed uses its desktop entry's Name=.
    function nameOverride(appId) {
        switch (appId) {
        case "google-chrome":
            return "Chrome";
        case "thunar":
            return "Thunar";
        }
        return "";
    }

    // Hint candidates in string `s` as {key, src, pos}, src being `src`:
    // word starts first (after a non-alphanumeric, or a capital after a
    // lowercase letter), then every other letter, each in order.
    function candidates(src, s) {
        const starts = [];
        const rest = [];
        let prev = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            const key = c.toLowerCase();
            if (key.length === 1 && hintKeys.includes(key)) {
                const isStart = prev === "" || !/[A-Za-z0-9]/.test(prev) || (/[A-Z]/.test(c) && /[a-z]/.test(prev));
                (isStart ? starts : rest).push({
                    "key": key,
                    "src": src,
                    "pos": i
                });
            }
            prev = c;
        }
        return starts.concat(rest);
    }

    // The window list in layout order, with each window's letter.
    function rebuild() {
        const wins = Niri.sortedWindows;
        const fallback = hintKeys.split("").map(k => ({
                    "key": k,
                    "src": "x",
                    "pos": -1
                }));
        const list = [];
        for (const w of wins) {
            const appId = w.app_id || "";
            const entry = Apps.entryFor(appId);
            const deskName = entry?.name ?? "";
            let name = nameOverride(appId.toLowerCase()) || deskName;
            if (!name) {
                name = (appId.split(".").pop() || "").replace(/[-_]/g, " ");
                name = name.charAt(0).toUpperCase() + name.slice(1);
            }
            name = name || "Window";

            // "Page - Google Chrome" -> "Page".
            let title = w.title || "";
            for (const sep of [" - ", " — ", " – "]) {
                let done = false;
                for (const n of [deskName, name]) {
                    const suffix = sep + n;
                    if (n && title.toLowerCase().endsWith(suffix.toLowerCase())) {
                        title = title.slice(0, title.length - suffix.length);
                        done = true;
                        break;
                    }
                }
                if (done)
                    break;
            }
            if (title.toLowerCase() === name.toLowerCase())
                title = "";

            const ws = Niri.workspaces[w.workspace_id] ?? null;
            list.push({
                "id": w.id,
                "appId": appId,
                "name": name,
                "title": title,
                "wsId": w.workspace_id,
                "wsIdx": ws ? ws.idx : "",
                "wsCurrent": ws ? ws.is_focused : false,
                "cands": candidates("n", name).concat(candidates("t", title), fallback)
            });
        }

        // A window keeps the letter it was first given; the underline goes on
        // that letter where it still occurs (the title may have changed),
        // else it's shown at the end of the row.
        const used = {};
        const open = {};
        for (const e of list)
            open[e.id] = true;
        for (const e of list) {
            const key = letters[e.id];
            if (!key || used[key])
                continue;
            const tok = e.cands.find(t => t.key === key);
            used[key] = true;
            e.key = key;
            e.src = tok.src;
            e.pos = tok.pos;
        }
        // New windows get letters in rounds: every one tries its best
        // candidate, then its second best, and so on, so no window's first
        // pick is taken by another window's tenth.
        for (let r = 0, progress = true; progress; r++) {
            progress = false;
            for (const e of list) {
                if (e.key || r >= e.cands.length)
                    continue;
                progress = true;
                const tok = e.cands[r];
                if (used[tok.key])
                    continue;
                used[tok.key] = true;
                e.key = tok.key;
                e.src = tok.src;
                e.pos = tok.pos;
            }
        }

        const kept = {};
        for (const e of list) {
            if (e.key)
                kept[e.id] = e.key;
            delete e.cands;
        }
        // (Not when the list came back empty, which can just be niri not
        // answering yet.)
        if (list.length > 0) {
            letters = kept;
            lettersFile.setText(JSON.stringify(kept));
        }
        entries = list;
    }

    // In-order (fuzzy) match of `query` in `text`, case-insensitive: the
    // matched positions, or null.
    function match(text, query) {
        const t = text.toLowerCase();
        const q = query.toLowerCase().replace(/\s+/g, "");
        const hits = [];
        let from = 0;
        for (const c of q) {
            const i = t.indexOf(c, from);
            if (i < 0)
                return null;
            hits.push(i);
            from = i + 1;
        }
        return hits;
    }

    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // A row's text as rich text: the app name bold, the hint letter
    // underlined in the accent colour, search matches in the accent colour.
    function rowText(e) {
        const accent = Theme.primary.toString();
        const hits = e.hits ?? [];
        const text = e.name + (e.title ? ": " + e.title : "");
        const hintAt = e.src === "n" ? e.pos : (e.src === "t" ? e.name.length + 2 + e.pos : -1);
        let out = "";
        for (let i = 0; i < text.length; i++) {
            let c = escapeHtml(text[i]);
            if (i === hintAt)
                c = "<u><font color=\"" + accent + "\">" + c + "</font></u>";
            else if (hits.includes(i))
                c = "<font color=\"" + accent + "\">" + c + "</font>";
            if (i < e.name.length)
                c = "<b>" + c + "</b>";
            out += c;
        }
        if (e.src === "x" && e.key)
            out += "&nbsp;&nbsp;<u><font color=\"" + accent + "\">" + e.key + "</font></u>";
        return out;
    }

    function move(delta) {
        const count = shownEntries.length;
        if (count > 0)
            list.currentIndex = (list.currentIndex + delta + count) % count;
    }

    function startSearch() {
        searching = true;
        message = "";
        input.text = "";
        list.currentIndex = 0;
    }

    function stopSearch() {
        searching = false;
        input.text = "";
        const i = entries.findIndex(e => e.id === fromId);
        list.currentIndex = Math.max(0, i);
    }

    function pressHint(key) {
        const e = entries.find(x => x.key === key);
        if (e)
            focusWindow(e.id);
        else
            message = "No window on " + key.toUpperCase();
    }

    function closeCurrent() {
        if (current)
            Niri.closeWindow(current.id);
    }

    IpcHandler {
        target: "switcher"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            if (!root.shown)
                root.show();
        }
        function close(): void {
            root.hide();
        }
    }

    // The list follows windows opening, closing and changing title while
    // it's up, keeping the highlight on the same window.
    Connections {
        target: Niri
        enabled: root.shown
        function onWindowsChanged() {
            const keep = root.current?.id;
            root.rebuild();
            const i = root.shownEntries.findIndex(e => e.id === keep);
            if (i >= 0)
                list.currentIndex = i;
            else
                list.currentIndex = Math.min(list.currentIndex, Math.max(0, root.shownEntries.length - 1));
        }
        // Focus moving to another window (a keybind, say) closes it. Taking
        // the keyboard itself shows up as focus on no window, so that
        // doesn't count.
        function onFocusedWindowIdChanged() {
            const id = Niri.focusedWindowId;
            if (id !== null && id !== undefined && id !== root.fromId)
                root.hide();
        }
    }

    // Letters per niri session: window ids restart with niri, so the file is
    // per niri socket.
    FileView {
        id: lettersFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qstest-switcher-letters." + (Quickshell.env("NIRI_SOCKET") || "none").split("/").pop() + ".json"
        printErrors: false
        onLoaded: {
            try {
                root.letters = JSON.parse(text()) || {};
            } catch (e) {
                root.letters = {};
            }
        }
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

        WlrLayershell.namespace: "qstest:switcher"
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

            readonly property real rowHeight: 36
            readonly property real pad: Theme.spacingS

            anchors.centerIn: parent
            width: Config.switcherWidth
            height: pad * 4 + field.height + rowHeight * Config.switcherVisibleRows + hintText.height
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

                StyledText {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.searching ? "/" : "›"
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeMedium + 2
                }

                TextInput {
                    id: input

                    anchors.left: prompt.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceText
                    selectionColor: Theme.primarySelected
                    selectedTextColor: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.weight: Theme.fontWeight
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    focus: true
                    // In letter mode it only takes keys: no text, no cursor.
                    cursorDelegate: Rectangle {
                        width: 1
                        color: Theme.surfaceText
                        visible: root.searching
                    }

                    onTextChanged: {
                        if (root.searching)
                            list.currentIndex = 0;
                    }

                    StyledText {
                        anchors.fill: parent
                        visible: input.text === ""
                        text: root.searching ? "search windows" : "press an underlined letter, or / to search"
                        color: Theme.withAlpha(Theme.surfaceText, 0.4)
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            if (root.searching)
                                root.stopSearch();
                            else
                                root.hide();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (root.current)
                                root.focusWindow(root.current.id);
                            break;
                        case Qt.Key_Down:
                        case Qt.Key_Tab:
                            root.move(1);
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_Backtab:
                            root.move(-1);
                            break;
                        case Qt.Key_Delete:
                            root.closeCurrent();
                            break;
                        case Qt.Key_Backspace:
                            if (!root.searching || input.text === "") {
                                if (root.searching)
                                    root.stopSearch();
                                break;
                            }
                            return;
                        default:
                            if (root.searching)
                                return;
                            if (event.text === "/") {
                                root.startSearch();
                            } else if (event.text.length === 1 && root.hintKeys.includes(event.text.toLowerCase()) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                                root.pressHint(event.text.toLowerCase());
                            } else {
                                // Nothing types in letter mode.
                                event.accepted = event.text !== "";
                                return;
                            }
                        }
                        event.accepted = true;
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
                height: panel.rowHeight * Config.switcherVisibleRows
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                model: root.shownEntries

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    // The workspace number on a workspace's first window (on
                    // every window while searching, when rows get filtered apart).
                    readonly property bool firstOfWorkspace: index === 0 || root.shownEntries[index - 1]?.wsId !== modelData.wsId

                    width: ListView.view.width
                    height: panel.rowHeight
                    radius: Theme.cornerRadius - panel.pad / 2
                    color: selected ? Theme.withAlpha(Theme.primary, 0.2) : (rowMouse.containsMouse ? Theme.widgetHover : "transparent")

                    // Gutter: workspace number, then a dot on the window you came from.
                    StyledText {
                        id: wsNumber
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignRight
                        visible: row.firstOfWorkspace || root.searching
                        text: String(row.modelData.wsIdx)
                        color: row.modelData.wsCurrent ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.4)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: row.modelData.wsCurrent ? Font.Bold : Theme.fontWeight
                        font.features: ({
                                "tnum": 1
                            })
                    }

                    Rectangle {
                        id: dot
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS + 18 + 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: row.modelData.wsCurrent ? Theme.primary : Theme.withAlpha(Theme.surfaceText, 0.4)
                        visible: row.modelData.id === root.fromId
                    }

                    IconImage {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS + 18 + 18
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 22
                        source: Apps.iconFor(row.modelData.appId) || Quickshell.iconPath("application-x-executable", true)
                        asynchronous: true
                    }

                    StyledText {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.rowText(row.modelData)
                        textFormat: Text.StyledText
                        color: row.selected ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.85)
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusWindow(row.modelData.id)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: root.searching && root.query !== "" ? "No windows match" : "No windows open"
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }

            StyledText {
                id: hintText
                anchors.bottom: parent.bottom
                anchors.bottomMargin: panel.pad
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - panel.pad * 4
                horizontalAlignment: Text.AlignHCenter
                text: root.message !== "" ? root.message : (root.searching ? "type to filter · ⏎ focus · del close · esc back to letters" : "letter or ⏎ focus · / search · del close · esc quit")
                color: root.message !== "" ? Theme.error : Theme.outline
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }
    }
}
