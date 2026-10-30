pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// What the dock shows: pinned apps in your order, then other running apps in
// niri's layout order. Apps
// are keyed by desktop entry id, which is what Settings.dockPins hold, so a
// window is matched to its pin through its app_id's desktop entry.
Singleton {
    id: root

    // [id, ...] for the dock's Repeater; items are looked up in `items`.
    readonly property var ids: model.ids
    // id -> { id, pinned, windows: [niri window, ...] }
    readonly property var items: model.items

    readonly property var model: {
        const pins = Settings.dockPins ?? [];
        const byApp = {};
        for (const w of Niri.sortedWindows) {
            const key = idForAppId(w.app_id);
            (byApp[key] = byApp[key] ?? []).push(w);
        }
        const ids = pins.slice();
        for (const key of Object.keys(byApp)) {
            if (!ids.includes(key))
                ids.push(key);
        }
        const items = {};
        for (const id of ids)
            items[id] = {
                "id": id,
                "pinned": pins.includes(id),
                "windows": byApp[id] ?? []
            };
        return {
            "ids": ids,
            "items": items
        };
    }

    // A window's app_id to the desktop entry id pins use (falls back to the
    // app_id itself when no entry matches).
    function idForAppId(appId) {
        const entry = Apps.entryFor(appId);
        return entry && entry.id ? entry.id : (appId || "");
    }

    function isPinned(id) {
        return (Settings.dockPins ?? []).includes(id);
    }

    function pin(id) {
        if (id && !isPinned(id))
            Settings.dockPins = (Settings.dockPins ?? []).concat([id]);
    }

    function unpin(id) {
        Settings.dockPins = (Settings.dockPins ?? []).filter(p => p !== id);
    }

    function togglePin(id) {
        if (isPinned(id))
            unpin(id);
        else
            pin(id);
    }

    // Moves a pin up (-1) or down (+1) in the order.
    function movePin(id, delta) {
        const pins = (Settings.dockPins ?? []).slice();
        const from = pins.indexOf(id);
        const to = from + delta;
        if (from < 0 || to < 0 || to >= pins.length)
            return;
        pins.splice(to, 0, pins.splice(from, 1)[0]);
        Settings.dockPins = pins;
    }

    function launch(id) {
        const entry = Apps.entryFor(id);
        if (entry)
            entry.execute();
    }

    // Not running: launch. Running: focus it; if it's already focused, step
    // to its next window.
    function activate(id) {
        const windows = items[id]?.windows ?? [];
        if (windows.length === 0) {
            launch(id);
            return;
        }
        const focused = windows.findIndex(w => w.id === Niri.focusedWindowId);
        Niri.focusWindow(windows[(focused + 1) % windows.length].id);
    }

    function closeAll(id) {
        for (const w of items[id]?.windows ?? [])
            Niri.closeWindow(w.id);
    }
}
