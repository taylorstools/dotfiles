pragma Singleton

import QtQuick
import Quickshell

// Desktop-entry lookups for window icons/names, and the launcher's search.
Singleton {
    id: root

    readonly property var applications: {
        const list = DesktopEntries.applications.values.filter(e => e && !e.noDisplay);
        list.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        return list;
    }

    function isSteamApp(appId) {
        return !!appId && /^steam_app_\d+$/.test(appId);
    }

    // Reading `applications` here makes every binding that calls this (icons,
    // names, dock pins) update once desktop entries finish loading; a lookup
    // made before that would otherwise stay on the fallback.
    function entryFor(appId) {
        if (!appId || applications.length === 0)
            return null;
        return DesktopEntries.heuristicLookup(appId) ?? null;
    }

    function resolveIcon(icon) {
        if (!icon)
            return "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.startsWith("file:") || icon.startsWith("image:"))
            return icon;
        return Quickshell.iconPath(icon, true);
    }

    function iconFor(appId) {
        if (!appId)
            return "";
        const steam = appId.match(/^steam_app_(\d+)$/);
        if (steam)
            return Quickshell.iconPath("steam_icon_" + steam[1], true);
        const entry = entryFor(appId);
        return resolveIcon(entry && entry.icon ? entry.icon : appId);
    }

    function nameFor(appId) {
        const entry = entryFor(appId);
        return entry && entry.name ? entry.name : (appId || "Unknown");
    }

    // Launcher search. Name matches rank above keyword/description matches;
    // a loose in-order letter match ("gimp" -> "GNU Image Manipulation
    // Program") comes last.
    function score(entry, query) {
        const name = (entry.name || "").toLowerCase();
        if (name === query)
            return 1000;
        if (name.startsWith(query))
            return 900 - name.length;
        const words = name.split(/[\s\-_.]+/);
        if (words.some(w => w.startsWith(query)))
            return 800 - name.length;
        const at = name.indexOf(query);
        if (at >= 0)
            return 700 - at;

        const extra = [entry.genericName || "", entry.id || "", (entry.keywords || []).join(" "), entry.comment || ""].join(" ").toLowerCase();
        if (extra.includes(query))
            return 500;

        let qi = 0;
        let gaps = 0;
        let last = -1;
        for (let i = 0; i < name.length && qi < query.length; i++) {
            if (name[i] === query[qi]) {
                if (last >= 0)
                    gaps += i - last - 1;
                last = i;
                qi++;
            }
        }
        if (qi === query.length)
            return Math.max(1, 300 - gaps);
        return 0;
    }

    function search(text) {
        const query = (text || "").trim().toLowerCase();
        if (query === "")
            return root.applications;
        const scored = [];
        for (const entry of root.applications) {
            const s = score(entry, query);
            if (s > 0)
                scored.push({
                    "entry": entry,
                    "score": s
                });
        }
        scored.sort((a, b) => b.score - a.score || (a.entry.name || "").localeCompare(b.entry.name || ""));
        return scored.map(s => s.entry);
    }
}
