pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Emoji for EmojiPicker/: every fully-qualified emoji in Unicode's
// emoji-test.txt (nixpkgs' unicode-emoji, linked into
// /run/current-system/sw/share by quickshell.nix), in its groups and order.
// Skin-tone variants aren't listed on their own: they hang off their base
// emoji as `tones`, and Settings.emojiSkinTone picks one. Variants with two
// tones (couples, handshakes) are left out. Picking types the emoji into the
// focused app with wtype; recents are in state.json.
Singleton {
    id: root

    // [{ e, name, group }], group indexing `groups`; `tones` is
    // { "light": "👍🏻", ... } on the emoji that have them.
    property var entries: []
    property var byChar: ({})
    property var groups: []
    property bool loaded: false
    // "wtype", or "none" (then picking only copies).
    property string typeMethod: ""

    readonly property int maxRecent: 30
    readonly property var tones: ["", "light", "medium-light", "medium", "medium-dark", "dark"]
    // The picker's swatches, Unicode's own Fitzpatrick colours.
    readonly property var toneColors: ({
            "": "#ffcc22",
            "light": "#f7dece",
            "medium-light": "#f3d2a2",
            "medium": "#d5ab88",
            "medium-dark": "#af7e57",
            "dark": "#7c533e"
        })
    readonly property var groupIcons: ({
            "Smileys & Emotion": "sentiment_satisfied",
            "People & Body": "waving_hand",
            "Animals & Nature": "pets",
            "Food & Drink": "restaurant",
            "Travel & Places": "flight",
            "Activities": "sports_soccer",
            "Objects": "lightbulb",
            "Symbols": "emoji_symbols",
            "Flags": "flag"
        })

    readonly property var recent: Settings.emojiRecent.map(e => byChar[e]).filter(e => e)

    // The emoji as shown and typed: with the chosen skin tone if it has one.
    function glyph(entry) {
        if (!entry)
            return "";
        return entry.tones?.[Settings.emojiSkinTone] ?? entry.e;
    }

    function inGroup(index) {
        return entries.filter(e => e.group === index);
    }

    // Every word has to appear in the name; names that start with the
    // query come first, then ones with a word that does.
    function search(query) {
        const q = query.toLowerCase().trim();
        if (q === "")
            return [];
        const words = q.split(/\s+/);
        const rank = e => e.name.startsWith(q) ? 0 : (e.name.includes(" " + words[0]) ? 1 : 2);
        return entries.filter(e => words.every(w => e.name.includes(w)))
            .map((e, i) => ({ e, i, r: rank(e) }))
            .sort((a, b) => a.r - b.r || a.i - b.i)
            .map(x => x.e);
    }

    function remember(entry) {
        Settings.emojiRecent = [entry.e].concat(Settings.emojiRecent.filter(e => e !== entry.e)).slice(0, maxRecent);
    }

    // Once the picker is gone and focus is back in the app, type it there.
    function type(entry) {
        if (typeMethod !== "wtype") {
            copy(entry);
            return;
        }
        remember(entry);
        typeTimer.text = glyph(entry);
        typeTimer.restart();
    }

    function copy(entry) {
        remember(entry);
        Quickshell.execDetached(["wl-copy", "--", glyph(entry)]);
    }

    function parse(text) {
        const list = [];
        const names = {};
        const chars = {};
        const groupNames = [];
        let group = -1;
        let skip = false;
        for (const line of text.split("\n")) {
            if (line.startsWith("# group: ")) {
                const name = line.slice(9).trim();
                // The bare skin-tone and hair swatches.
                skip = name === "Component";
                if (!skip) {
                    groupNames.push(name);
                    group = groupNames.length - 1;
                }
                continue;
            }
            const hash = line.indexOf("# ");
            if (skip || hash < 0 || !line.includes("; fully-qualified"))
                continue;
            // "😀 E1.0 grinning face"
            const [e, , ...rest] = line.slice(hash + 2).split(" ");
            const name = rest.join(" ");
            if (name.includes("skin tone")) {
                const m = name.match(/^(.*): (light|medium-light|medium|medium-dark|dark) skin tone$/);
                const base = m ? names[m[1]] : null;
                if (base) {
                    base.tones = base.tones ?? {};
                    base.tones[m[2]] = e;
                }
                continue;
            }
            const entry = { e, name, group };
            list.push(entry);
            names[name] = entry;
            chars[e] = entry;
        }
        groups = groupNames;
        byChar = chars;
        entries = list;
        loaded = true;
    }

    Timer {
        id: typeTimer

        property string text: ""

        interval: 200
        onTriggered: Quickshell.execDetached(["wtype", "--", text])
    }

    Process {
        running: true
        command: ["sh", "-c", 'IFS=:; for d in ${XDG_DATA_DIRS:-/run/current-system/sw/share}; do f="$d/unicode/emoji/emoji-test.txt"; [ -r "$f" ] && exec grep -E "^# group: |; fully-qualified" "$f"; done; exit 1']
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: code => {
            if (code !== 0)
                console.warn("Emoji: no unicode/emoji/emoji-test.txt in XDG_DATA_DIRS (unicode-emoji, quickshell.nix)");
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v wtype >/dev/null && echo wtype || echo none"]
        stdout: StdioCollector {
            onStreamFinished: root.typeMethod = text.trim()
        }
    }
}
