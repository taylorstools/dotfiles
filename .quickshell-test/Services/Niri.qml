pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// niri state over its IPC socket: workspaces, windows, focus, and each
// window's position in the scrolling layout (used to order running apps the
// way DMS does). Actions go back over a second socket.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET")
    readonly property bool available: socketPath !== ""

    // id -> object, exactly as niri sends them.
    property var workspaces: ({})
    property var windows: ({})
    property var focusedWindowId: null

    readonly property var workspaceList: Object.values(workspaces).sort((a, b) => a.idx - b.idx)
    readonly property var sortedWindows: sortWindows(Object.values(windows), workspaces)
    readonly property string focusedOutput: {
        const ws = Object.values(workspaces).find(w => w.is_focused);
        return ws ? (ws.output || "") : "";
    }

    function workspacesForOutput(outputName) {
        return workspaceList.filter(w => !outputName || w.output === outputName);
    }

    function activeWorkspaceId(outputName) {
        const ws = workspaceList.find(w => w.is_active && (!outputName || w.output === outputName));
        return ws ? ws.id : -1;
    }

    // Same ordering as DMS: output, workspace index, column, row in column.
    function sortWindows(list, wsMap) {
        const keyed = list.map(w => {
            const ws = wsMap[w.workspace_id];
            const pos = w.layout ? w.layout.pos_in_scrolling_layout : null;
            return {
                "window": w,
                "output": ws ? (ws.output || "") : "~",
                "wsIdx": ws ? ws.idx : 999999,
                "col": (pos && pos.length >= 2) ? pos[0] : 999999,
                "row": (pos && pos.length >= 2) ? pos[1] : 999999
            };
        });
        keyed.sort((a, b) => {
            if (a.output !== b.output)
                return a.output < b.output ? -1 : 1;
            if (a.wsIdx !== b.wsIdx)
                return a.wsIdx - b.wsIdx;
            if (a.col !== b.col)
                return a.col - b.col;
            if (a.row !== b.row)
                return a.row - b.row;
            return a.window.id - b.window.id;
        });
        return keyed.map(k => k.window);
    }

    // Actions

    function send(request) {
        if (!requestSocket.connected)
            return false;
        requestSocket.write(JSON.stringify(request) + "\n");
        requestSocket.flush();
        return true;
    }

    function focusWindow(id) {
        send({
            "Action": {
                "FocusWindow": {
                    "id": id
                }
            }
        });
    }

    function closeWindow(id) {
        send({
            "Action": {
                "CloseWindow": {
                    "id": id
                }
            }
        });
    }

    function focusWorkspace(id) {
        send({
            "Action": {
                "FocusWorkspace": {
                    "reference": {
                        "Id": id
                    }
                }
            }
        });
    }

    function focusWorkspaceRelative(delta) {
        send({
            "Action": delta > 0 ? {
                "FocusWorkspaceDown": {}
            } : {
                "FocusWorkspaceUp": {}
            }
        });
    }

    // Event stream

    function updateWindow(id, changes) {
        const current = root.windows[id];
        if (!current)
            return;
        const next = Object.assign({}, root.windows);
        next[id] = Object.assign({}, current, changes);
        root.windows = next;
    }

    function handleEvent(event) {
        const type = Object.keys(event)[0];
        const data = event[type];

        switch (type) {
        case "WorkspacesChanged":
            {
                const next = {};
                for (const ws of data.workspaces)
                    next[ws.id] = ws;
                root.workspaces = next;
                break;
            }
        case "WorkspaceActivated":
            {
                const target = root.workspaces[data.id];
                if (!target)
                    break;
                const next = {};
                for (const key in root.workspaces) {
                    const ws = Object.assign({}, root.workspaces[key]);
                    if (ws.output === target.output)
                        ws.is_active = ws.id === data.id;
                    if (data.focused)
                        ws.is_focused = ws.id === data.id;
                    next[key] = ws;
                }
                root.workspaces = next;
                break;
            }
        case "WorkspaceActiveWindowChanged":
            {
                const ws = root.workspaces[data.workspace_id];
                if (!ws)
                    break;
                const next = Object.assign({}, root.workspaces);
                next[data.workspace_id] = Object.assign({}, ws, {
                    "active_window_id": data.active_window_id
                });
                root.workspaces = next;
                break;
            }
        case "WorkspaceUrgencyChanged":
            {
                const ws = root.workspaces[data.id];
                if (!ws)
                    break;
                const next = Object.assign({}, root.workspaces);
                next[data.id] = Object.assign({}, ws, {
                    "is_urgent": data.urgent
                });
                root.workspaces = next;
                break;
            }
        case "WindowsChanged":
            {
                const next = {};
                let focused = null;
                for (const w of data.windows) {
                    next[w.id] = w;
                    if (w.is_focused)
                        focused = w.id;
                }
                root.windows = next;
                root.focusedWindowId = focused;
                break;
            }
        case "WindowOpenedOrChanged":
            {
                const w = data.window;
                const next = Object.assign({}, root.windows);
                if (w.is_focused) {
                    for (const key in next) {
                        if (next[key].is_focused)
                            next[key] = Object.assign({}, next[key], {
                                "is_focused": false
                            });
                    }
                    root.focusedWindowId = w.id;
                }
                next[w.id] = w;
                root.windows = next;
                break;
            }
        case "WindowClosed":
            {
                const next = Object.assign({}, root.windows);
                delete next[data.id];
                root.windows = next;
                if (root.focusedWindowId === data.id)
                    root.focusedWindowId = null;
                break;
            }
        case "WindowFocusChanged":
            {
                const next = {};
                for (const key in root.windows) {
                    const w = root.windows[key];
                    const focused = w.id === data.id;
                    next[key] = w.is_focused === focused ? w : Object.assign({}, w, {
                        "is_focused": focused
                    });
                }
                root.windows = next;
                root.focusedWindowId = data.id;
                break;
            }
        case "WindowLayoutsChanged":
            {
                const next = Object.assign({}, root.windows);
                for (const change of data.changes) {
                    const id = change[0];
                    if (next[id])
                        next[id] = Object.assign({}, next[id], {
                            "layout": change[1]
                        });
                }
                root.windows = next;
                break;
            }
        case "WindowUrgencyChanged":
            updateWindow(data.id, {
                "is_urgent": data.urgent
            });
            break;
        }
    }

    Socket {
        id: eventSocket
        path: root.socketPath
        connected: root.available

        onConnectionStateChanged: {
            if (connected) {
                write("\"EventStream\"\n");
                flush();
            }
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    root.handleEvent(JSON.parse(line));
                } catch (e) {
                    console.warn("Niri: unparseable event line:", line);
                }
            }
        }
    }

    Socket {
        id: requestSocket
        path: root.socketPath
        connected: root.available

        parser: SplitParser {
            onRead: _ => {}
        }
    }
}
