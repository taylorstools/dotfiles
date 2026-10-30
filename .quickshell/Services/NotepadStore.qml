pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Notepad tabs and where their text lives: notepad-session.json next to a
// notepad-files/ folder.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    readonly property string baseDir: stateHome + "/qstest/notepad"

    property var tabs: []
    property int currentIndex: 0
    property bool ready: false
    readonly property var currentTab: tabs[currentIndex] ?? null
    readonly property string currentPath: pathOf(currentTab)

    // Scratch tabs store a path relative to baseDir, opened files a full one.
    function pathOf(tab) {
        if (!tab)
            return "";
        return tab.isTemporary ? baseDir + "/" + tab.filePath : tab.filePath;
    }

    // "~/x" and "x" both mean a path under $HOME.
    function resolvePath(path) {
        if (path === "~")
            return home;
        if (path.startsWith("~/"))
            return home + path.slice(1);
        return path.startsWith("/") ? path : home + "/" + path;
    }

    function makeTab(props) {
        const id = Date.now();
        return Object.assign({
            id: id,
            title: "Untitled",
            filePath: "notepad-files/untitled-" + id + ".txt",
            isTemporary: true,
            lastModified: new Date().toISOString(),
            cursorPosition: 0,
            scrollPosition: 0
        }, props || {});
    }

    function addTab() {
        tabs = tabs.concat([makeTab()]);
        currentIndex = tabs.length - 1;
        save();
    }

    // Opens a file in a new tab, or switches to it if it's already open.
    function openFile(path) {
        const existing = tabs.findIndex(t => !t.isTemporary && t.filePath === path);
        if (existing >= 0) {
            switchTo(existing);
            return;
        }
        tabs = tabs.concat([makeTab({
                title: path.split("/").pop(),
                filePath: path,
                isTemporary: false
            })]);
        currentIndex = tabs.length - 1;
        save();
    }

    // Closing a scratch tab deletes its file; opened files stay.
    // Closing the last tab leaves a fresh empty one.
    function closeTab(index) {
        const tab = tabs[index];
        if (!tab)
            return;
        if (tab.isTemporary)
            Quickshell.execDetached(["rm", "-f", pathOf(tab)]);
        const next = tabs.slice();
        next.splice(index, 1);
        if (next.length === 0)
            next.push(makeTab());
        let current = currentIndex;
        if (current > index || current >= next.length)
            current--;
        tabs = next;
        currentIndex = Math.max(0, current);
        save();
    }

    function switchTo(index) {
        if (index < 0 || index >= tabs.length || index === currentIndex)
            return;
        currentIndex = index;
        save();
    }

    function updateTab(index, props) {
        if (!tabs[index])
            return;
        const next = tabs.slice();
        next[index] = Object.assign({}, next[index], props, {
            lastModified: new Date().toISOString()
        });
        tabs = next;
        save();
    }

    // Called once the text has been written to `path`.
    function saveTabAs(index, path) {
        const tab = tabs[index];
        if (!tab)
            return;
        if (tab.isTemporary)
            Quickshell.execDetached(["rm", "-f", pathOf(tab)]);
        updateTab(index, {
            title: path.split("/").pop(),
            filePath: path,
            isTemporary: false
        });
    }

    function save() {
        if (!ready)
            return;
        sessionFile.setText(JSON.stringify({
            version: 1,
            currentTabIndex: currentIndex,
            tabs: tabs
        }, null, 2));
    }

    function finishLoading() {
        if (tabs.length === 0)
            tabs = [makeTab()];
        currentIndex = Math.max(0, Math.min(currentIndex, tabs.length - 1));
        ready = true;
        save();
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.baseDir + "/notepad-files"]
        onExited: sessionFile.path = root.baseDir + "/notepad-session.json"
    }

    FileView {
        id: sessionFile
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.tabs = data.tabs || [];
                root.currentIndex = data.currentTabIndex || 0;
            } catch (e) {
                console.warn("NotepadStore: could not parse", path, e);
            }
            root.finishLoading();
        }
        onLoadFailed: root.finishLoading()
    }
}
