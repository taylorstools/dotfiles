pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Clipboard history. `wl-paste --watch` runs Clipboard/clip-helper.sh on every
// copy, which saves the content under ~/.local/state/qstest/clipboard and
// reports it here; index.json keeps the list (newest first) with pins.
// Copying something already in the history moves it back to the top.
// Limits: 100 unpinned entries, 5 MB each.
// Pasting copies the entry, then types Ctrl+V into the window that had focus
// (Ctrl+Shift+V in terminals) with wtype; without wtype it only copies.
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qstest/clipboard"
    readonly property string helper: Quickshell.shellDir + "/Clipboard/clip-helper.sh"
    readonly property int maxUnpinned: 100

    // [{ id, kind: "text" | "image", hash, bytes, preview, time, pinned }]
    property var entries: []
    property bool loaded: false
    // "wtype", or "none" until it's installed (then pasting only copies).
    property string pasteMethod: ""

    // Terminals: these get Ctrl+Shift+V.
    readonly property var terminalAppIds: ["kitty", "foot", "footclient", "alacritty", "st", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "ghostty", "org.kde.konsole", "konsole", "org.gnome.terminal", "gnome-terminal-server", "org.gnome.console", "kgx", "com.gexperts.tilix", "tilix", "terminator", "xfce4-terminal", "lxterminal", "deepin-terminal", "io.elementary.terminal", "rio", "contour", "wayst", "urxvt", "rxvt"]

    function fileFor(entry) {
        return dir + "/" + entry.id + (entry.kind === "image" ? ".png" : ".txt");
    }

    function isTerminal(appId) {
        const id = (appId || "").toLowerCase();
        return id !== "" && (terminalAppIds.includes(id) || id.endsWith("term") || id.includes("terminal"));
    }

    function setEntries(list) {
        entries = list;
        saveDelay.restart();
    }

    function removeFiles(list) {
        if (list.length > 0)
            Quickshell.execDetached(["rm", "-f"].concat(list.map(e => fileFor(e))));
    }

    function togglePin(id) {
        setEntries(entries.map(e => e.id === id ? Object.assign({}, e, {
                "pinned": !e.pinned
            }) : e));
    }

    function remove(id) {
        removeFiles(entries.filter(e => e.id === id));
        setEntries(entries.filter(e => e.id !== id));
    }

    // Clear all; pinned entries go too unless that setting is off.
    function clear() {
        const keep = Settings.clipboardClearPinned ? [] : entries.filter(e => e.pinned);
        removeFiles(entries.filter(e => !keep.includes(e)));
        setEntries(keep);
    }

    function copy(entry) {
        Quickshell.execDetached(["bash", helper, "copy", fileFor(entry), entry.kind]);
    }

    // Copy, then once the panel is gone and focus is back on `appId`'s
    // window, type the paste shortcut.
    function paste(entry, appId) {
        copy(entry);
        if (pasteMethod === "none")
            return;
        pasteTimer.terminal = isTerminal(appId);
        pasteTimer.restart();
    }

    // A line from clip-helper.sh capture.
    function add(line) {
        const [id, kind, hash, bytes, ...rest] = line.split("\t");
        if (!id || !kind)
            return;
        const preview = rest.join(" ").replace(/\s+/g, " ").trim().slice(0, 300);
        const existing = entries.find(e => e.hash === hash);
        const entry = {
            "id": id,
            "kind": kind,
            "hash": hash,
            "bytes": parseInt(bytes) || 0,
            "preview": preview,
            "time": Date.now(),
            "pinned": existing ? existing.pinned : false
        };
        // Copied again: keep the new file, drop the old copy of it.
        if (existing)
            removeFiles([existing]);
        let list = [entry].concat(entries.filter(e => e.hash !== hash));
        const unpinned = list.filter(e => !e.pinned);
        if (unpinned.length > maxUnpinned) {
            const dropped = unpinned.slice(maxUnpinned);
            removeFiles(dropped);
            list = list.filter(e => !dropped.includes(e));
        }
        setEntries(list);
    }

    // "Clear history at login": the marker in $XDG_RUNTIME_DIR lives until
    // logout, so Quickshell reloading the config doesn't clear it again.
    function startSession() {
        sessionCheck.running = true;
    }

    FileView {
        id: indexFile
        path: root.dir + "/index.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                root.entries = JSON.parse(text());
            } catch (e) {
                root.entries = [];
            }
            root.loaded = true;
            root.startSession();
        }
        onLoadFailed: {
            root.loaded = true;
            root.startSession();
        }
    }

    Timer {
        id: saveDelay
        interval: 300
        onTriggered: mkdir.running = true
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        onExited: indexFile.setText(JSON.stringify(root.entries))
    }

    Process {
        id: sessionCheck
        command: ["sh", "-c", 'm="${XDG_RUNTIME_DIR:-/tmp}/qstest-clipboard-session"; [ -e "$m" ] && echo old || { touch "$m"; echo new; }']
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "new" && Settings.clipboardClearOnStartup)
                    root.clear();
                watcher.running = true;
            }
        }
    }

    // Started once the index is loaded, so new copies land in the right list.
    Process {
        id: watcher
        command: ["wl-paste", "--watch", "bash", root.helper, "capture", root.dir]
        stdout: SplitParser {
            onRead: line => root.add(line)
        }
    }

    Timer {
        id: pasteTimer

        property bool terminal: false

        interval: 200
        onTriggered: Quickshell.execDetached(["bash", root.helper, "paste", terminal ? "1" : "0"])
    }

    Process {
        running: true
        command: ["bash", root.helper, "method"]
        stdout: StdioCollector {
            onStreamFinished: root.pasteMethod = text.trim()
        }
    }

    IpcHandler {
        target: "cliphistory"

        function clear(): void {
            root.clear();
        }
    }
}
