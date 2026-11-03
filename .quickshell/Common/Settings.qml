pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Settings changed from the settings window and the wallpaper IPC. They're
// saved as settings.json in this folder so they live with the rest of the
// dotfiles. Config.qml is still where the hand-edited settings go.
//
// What changes by itself (the wallpaper, every few minutes with auto-change)
// or by the minute (do not disturb, night light) is state, not settings: it
// goes to ~/.local/state/qstest/state.json, so settings.json only changes in
// git when a setting does. Both are read through the same properties here.
Singleton {
    id: root

    readonly property string path: Quickshell.shellDir + "/settings.json"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qstest"
    readonly property string statePath: stateDir + "/state.json"
    // The keys that live in state.json (and were in settings.json before).
    readonly property var stateKeys: ["wallpaperPath", "doNotDisturb", "nightLight", "nightLightTemperature"]

    // Defaults: Taylor's lock and sleep commands, and plain systemctl for
    // restart and shut down.
    readonly property var defaults: ({
            "lockCommand": "$HOME/scripts/hypridle/lock-session.sh --force",
            "sleepCommand": "$HOME/scripts/hypridle/lock-session.sh & sleep 1; systemctl suspend",
            "restartCommand": "systemctl reboot",
            "shutdownCommand": "systemctl poweroff",
            "logoutCommand": "niri msg action quit --skip-confirmation",
            "windowsCommand": "$HOME/scripts/refind_boot-to-windows.sh",
            // Which of the power menu's buttons show.
            "powerMenuShowLock": true,
            "powerMenuShowLogout": true,
            "powerMenuShowSleep": true,
            "powerMenuShowShutdown": true,
            "powerMenuShowReboot": true,
            "powerMenuShowWindows": true,
            // The key press menu (Mod+X): a key, what it says, what it runs
            // (with sh -c). Settings > Key press menu.
            "keyPressEntries": [
                { "key": "r", "desc": "Run", "cmd": "qs ipc call runner toggle" },
                { "key": "t", "desc": "Terminal (Root)", "cmd": "ghostty -e sudo -i" },
                { "key": "e", "desc": "File Explorer (Root)", "cmd": "sudo -EH thunar" },
                { "key": "m", "desc": "Task Manager", "cmd": "missioncenter" },
                { "key": "k", "desc": "Disk Management", "cmd": "sudo -EH gparted" },
                { "key": "s", "desc": "Snipping Tool", "cmd": "qs ipc call snip open" },
                { "key": "o", "desc": "OCR Select and Copy", "cmd": "$HOME/scripts/ocr-snip.sh" },
                { "key": "b", "desc": "Toggle Night Mode", "cmd": "qs ipc call night toggle" },
                { "key": "n", "desc": "Night Mode Strength", "cmd": "qs ipc call nightpanel toggle" },
                { "key": "a", "desc": "Toggle Keep Awake", "cmd": "$HOME/scripts/hypridle/toggle-hypridle.sh" },
                { "key": "w", "desc": "Change Wallpaper", "cmd": "qs ipc call wallpaper random" },
                { "key": "d", "desc": "Change Refresh Rate", "cmd": "$HOME/scripts/niri_change-refresh-rate.sh" },
                { "key": "y", "desc": "Toggle Voice-to-Text", "cmd": "whisrs toggle" },
                { "key": "p", "desc": "Power", "cmd": "qs ipc call powermenu toggle" }
            ],
            // Wallpaper, its folder, and the matugen scheme.
            "wallpaperPath": Quickshell.env("HOME") + "/.dotfiles/Wallpapers/enlarge_1077194.png",
            "wallpaperFolder": Quickshell.env("HOME") + "/.dotfiles/Wallpapers",
            "matugenScheme": "scheme-neutral",
            // Off: matugen builds the palette from the wallpaper's dominant
            // colour. On: from its most saturated one (closer to wallust).
            "colorfulSeed": false,
            // Surface tint: how much of a colour is mixed into the bar, panel
            // and container backgrounds (0..1), and which colour: matugen's
            // "primary", "secondary" or "tertiary", or "custom" (the hex below).
            "surfaceTint": 0,
            "surfaceTintColor": "primary",
            "surfaceTintCustom": "#7aa2f7",
            // Border of every panel and flyout (not the taskbar): the same
            // choices as the tint, plus "outline" and "text", and its opacity.
            "borderColor": "primary",
            "borderColorCustom": "#ffffff",
            "borderOpacity": 0.8,
            // Whether the attached control center, calendar flyout and notepad
            // get that border too (floating, they always do).
            "attachedPanelBorder": false,
            // One opacity for every panel's background,
            // compositor blur behind them, and niri's blur reach in logical px
            // (offset = strength / 14).
            // Fonts: the shell's font and weight ("regular" or "medium"), and
            // the monospace one for command and colour fields.
            "fontFamily": "Inter",
            "fontWeight": "medium",
            "monoFontFamily": "monospace",
            "surfaceOpacity": 0.8,
            // The control center, calendar flyout and notepad sit against the
            // taskbar and screen edge with square corners (Windows 10 style);
            // off, they float with a gap and rounded corners.
            "attachPanels": true,
            // Corner radius of the control center and calendar flyout, in px,
            // attached or floating.
            "flyoutRadius": 12,
            "blur": true,
            "blurStrength": 50,
            // X-ray blur: blurred panels show only the wallpaper behind them,
            // not the windows (niri's background-effect xray).
            "blurXray": true,
            // Clipboard: "Clear all" removes pinned entries too, and the
            // history is cleared at login (Taylor's choice);
            // with the first off, pinned entries survive both.
            "clipboardClearPinned": true,
            // Open/close and slide animations everywhere, in ms; 0 turns them
            // off. The wallpaper crossfade has its own.
            "animationDuration": 110,
            // Night light: off, and its temperature when turned on.
            "nightLight": false,
            "nightLightTemperature": 3000,
            "doNotDisturb": false,
            // Emoji picker: the last ones picked, newest first, and the skin
            // tone for emoji that have one ("" = the default yellow).
            "emojiRecent": [],
            "emojiSkinTone": "",
            // Opacity of the grey fills inside panels (cards, rows, fields,
            // buttons); 1 keeps them solid.
            "overlayOpacity": 1,
            "wallpaperFadeDuration": 500,
            // A random wallpaper from the folder at login, and every
            // wallpaperChangeInterval minutes while wallpaperAutoChange is on.
            "wallpaperChangeAtStartup": true,
            "wallpaperAutoChange": true,
            "wallpaperChangeInterval": 15,
            "clipboardClearOnStartup": true,
            // In the overview the taskbar moves under windows (niri's bottom
            // layer), so it zooms out with the workspace; the rest of the time
            // it stays above windows. Off keeps it fixed on screen in the
            // overview too.
            "barZoomsWithOverview": true,
            // Notification pop-ups: "bottom-right" (above the taskbar) or "top-right".
            "notificationPosition": "bottom-right",
            // Taskbar running apps (the Better Running Apps plugin's settings,
            // Taylor's values). Widths in px; a max
            // width of 0 uses the percentage instead.
            "runningAppsLargeIcons": true,
            "runningAppsCurrentWorkspaceOnly": false,
            "runningAppsGroupByApp": false,
            "runningAppsMaxWidthPercent": 100,
            "runningAppsMaxWidth": 0,
            "runningAppsFullTitleWidth": 120,
            "runningAppsMinTitleWidth": 32,
            "runningAppsReservedWidth": 300,
            // The dock and its pinned apps (desktop entry ids).
            "dockEnabled": true,
            "dockPosition": "left",
            "dockAutoHide": true,
            "dockBorder": true,
            "dockIconSize": 30,
            "dockSpacing": 8,
            "dockPins": ["thunar", "org.kde.krdc", "com.mitchellh.ghostty", "com.anthropic.Claude", "codium", "md.obsidian.Obsidian", "davinci-resolve-studio", "firefox", "google-chrome"]
        })

    property alias lockCommand: adapter.lockCommand
    property alias sleepCommand: adapter.sleepCommand
    property alias restartCommand: adapter.restartCommand
    property alias shutdownCommand: adapter.shutdownCommand
    property alias logoutCommand: adapter.logoutCommand
    property alias windowsCommand: adapter.windowsCommand
    property alias powerMenuShowLock: adapter.powerMenuShowLock
    property alias powerMenuShowLogout: adapter.powerMenuShowLogout
    property alias powerMenuShowSleep: adapter.powerMenuShowSleep
    property alias powerMenuShowShutdown: adapter.powerMenuShowShutdown
    property alias powerMenuShowReboot: adapter.powerMenuShowReboot
    property alias powerMenuShowWindows: adapter.powerMenuShowWindows
    property alias keyPressEntries: adapter.keyPressEntries
    property alias wallpaperPath: stateAdapter.wallpaperPath
    property alias wallpaperFolder: adapter.wallpaperFolder
    property alias matugenScheme: adapter.matugenScheme
    property alias colorfulSeed: adapter.colorfulSeed
    property alias surfaceTint: adapter.surfaceTint
    property alias fontFamily: adapter.fontFamily
    property alias fontWeight: adapter.fontWeight
    property alias monoFontFamily: adapter.monoFontFamily
    property alias surfaceTintColor: adapter.surfaceTintColor
    property alias surfaceTintCustom: adapter.surfaceTintCustom
    property alias borderColor: adapter.borderColor
    property alias borderColorCustom: adapter.borderColorCustom
    property alias borderOpacity: adapter.borderOpacity
    property alias attachedPanelBorder: adapter.attachedPanelBorder
    property alias surfaceOpacity: adapter.surfaceOpacity
    property alias blur: adapter.blur
    property alias blurStrength: adapter.blurStrength
    property alias attachPanels: adapter.attachPanels
    property alias flyoutRadius: adapter.flyoutRadius
    property alias blurXray: adapter.blurXray
    property alias clipboardClearPinned: adapter.clipboardClearPinned
    property alias animationDuration: adapter.animationDuration
    property alias nightLight: stateAdapter.nightLight
    property alias nightLightTemperature: stateAdapter.nightLightTemperature
    property alias overlayOpacity: adapter.overlayOpacity
    property alias wallpaperFadeDuration: adapter.wallpaperFadeDuration
    property alias wallpaperChangeAtStartup: adapter.wallpaperChangeAtStartup
    property alias wallpaperAutoChange: adapter.wallpaperAutoChange
    property alias wallpaperChangeInterval: adapter.wallpaperChangeInterval
    property alias clipboardClearOnStartup: adapter.clipboardClearOnStartup
    property alias doNotDisturb: stateAdapter.doNotDisturb
    property alias emojiRecent: stateAdapter.emojiRecent
    property alias emojiSkinTone: stateAdapter.emojiSkinTone
    property alias barZoomsWithOverview: adapter.barZoomsWithOverview
    property alias notificationPosition: adapter.notificationPosition
    property alias runningAppsLargeIcons: adapter.runningAppsLargeIcons
    property alias runningAppsCurrentWorkspaceOnly: adapter.runningAppsCurrentWorkspaceOnly
    property alias runningAppsGroupByApp: adapter.runningAppsGroupByApp
    property alias runningAppsMaxWidthPercent: adapter.runningAppsMaxWidthPercent
    property alias runningAppsMaxWidth: adapter.runningAppsMaxWidth
    property alias runningAppsFullTitleWidth: adapter.runningAppsFullTitleWidth
    property alias runningAppsMinTitleWidth: adapter.runningAppsMinTitleWidth
    property alias runningAppsReservedWidth: adapter.runningAppsReservedWidth
    property alias dockEnabled: adapter.dockEnabled
    property alias dockPosition: adapter.dockPosition
    property alias dockAutoHide: adapter.dockAutoHide
    property alias dockBorder: adapter.dockBorder
    property alias dockIconSize: adapter.dockIconSize
    property alias dockSpacing: adapter.dockSpacing
    property alias dockPins: adapter.dockPins

    // settings.json and state.json have been read (or found missing): until
    // then every setting is its default.
    readonly property bool ready: _settingsRead && _stateRead
    property bool _settingsRead: false
    property bool _stateRead: false

    function reset(key) {
        root[key] = defaults[key];
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: saveTimer.restart()
        onLoaded: root._settingsRead = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
            root._settingsRead = true;
        }

        JsonAdapter {
            id: adapter

            property string lockCommand: root.defaults.lockCommand
            property string sleepCommand: root.defaults.sleepCommand
            property string restartCommand: root.defaults.restartCommand
            property string shutdownCommand: root.defaults.shutdownCommand
            property string logoutCommand: root.defaults.logoutCommand
            property string windowsCommand: root.defaults.windowsCommand
            property bool powerMenuShowLock: root.defaults.powerMenuShowLock
            property bool powerMenuShowLogout: root.defaults.powerMenuShowLogout
            property bool powerMenuShowSleep: root.defaults.powerMenuShowSleep
            property bool powerMenuShowShutdown: root.defaults.powerMenuShowShutdown
            property bool powerMenuShowReboot: root.defaults.powerMenuShowReboot
            property bool powerMenuShowWindows: root.defaults.powerMenuShowWindows
            property var keyPressEntries: root.defaults.keyPressEntries
            property string wallpaperFolder: root.defaults.wallpaperFolder
            property string matugenScheme: root.defaults.matugenScheme
            property bool colorfulSeed: root.defaults.colorfulSeed
            property real surfaceTint: root.defaults.surfaceTint
            property string fontFamily: root.defaults.fontFamily
            property string fontWeight: root.defaults.fontWeight
            property string monoFontFamily: root.defaults.monoFontFamily
            property string surfaceTintColor: root.defaults.surfaceTintColor
            property string surfaceTintCustom: root.defaults.surfaceTintCustom
            property string borderColor: root.defaults.borderColor
            property string borderColorCustom: root.defaults.borderColorCustom
            property real borderOpacity: root.defaults.borderOpacity
            property bool attachedPanelBorder: root.defaults.attachedPanelBorder
            property real surfaceOpacity: root.defaults.surfaceOpacity
            property bool blur: root.defaults.blur
            property int blurStrength: root.defaults.blurStrength
            property bool attachPanels: root.defaults.attachPanels
            property int flyoutRadius: root.defaults.flyoutRadius
            property bool blurXray: root.defaults.blurXray
            property bool clipboardClearPinned: root.defaults.clipboardClearPinned
            property int animationDuration: root.defaults.animationDuration
            property real overlayOpacity: root.defaults.overlayOpacity
            property int wallpaperFadeDuration: root.defaults.wallpaperFadeDuration
            property bool wallpaperChangeAtStartup: root.defaults.wallpaperChangeAtStartup
            property bool wallpaperAutoChange: root.defaults.wallpaperAutoChange
            property int wallpaperChangeInterval: root.defaults.wallpaperChangeInterval
            property bool clipboardClearOnStartup: root.defaults.clipboardClearOnStartup
            property bool barZoomsWithOverview: root.defaults.barZoomsWithOverview
            property string notificationPosition: root.defaults.notificationPosition
            property bool runningAppsLargeIcons: root.defaults.runningAppsLargeIcons
            property bool runningAppsCurrentWorkspaceOnly: root.defaults.runningAppsCurrentWorkspaceOnly
            property bool runningAppsGroupByApp: root.defaults.runningAppsGroupByApp
            property int runningAppsMaxWidthPercent: root.defaults.runningAppsMaxWidthPercent
            property int runningAppsMaxWidth: root.defaults.runningAppsMaxWidth
            property int runningAppsFullTitleWidth: root.defaults.runningAppsFullTitleWidth
            property int runningAppsMinTitleWidth: root.defaults.runningAppsMinTitleWidth
            property int runningAppsReservedWidth: root.defaults.runningAppsReservedWidth
            property bool dockEnabled: root.defaults.dockEnabled
            property string dockPosition: root.defaults.dockPosition
            property bool dockAutoHide: root.defaults.dockAutoHide
            property bool dockBorder: root.defaults.dockBorder
            property int dockIconSize: root.defaults.dockIconSize
            property int dockSpacing: root.defaults.dockSpacing
            property var dockPins: root.defaults.dockPins
        }
    }

    // Typing in a field changes a value per keystroke; write once it settles.
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: file.writeAdapter()
    }

    // First run with state.json: take these from settings.json, where they
    // used to be, so nothing resets.
    function migrateState() {
        let old = {};
        try {
            old = JSON.parse(file.text()) || {};
        } catch (e) {}
        for (const key of stateKeys) {
            if (old[key] !== undefined)
                stateAdapter[key] = old[key];
        }
    }

    // Read once settings.json has been, so a migration can see it.
    FileView {
        id: stateFile
        path: root._settingsRead ? root.statePath : ""
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: stateSaveTimer.restart()
        onLoaded: root._stateRead = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.migrateState();
                stateSaveTimer.restart();
            }
            root._stateRead = true;
        }

        JsonAdapter {
            id: stateAdapter

            property string wallpaperPath: root.defaults.wallpaperPath
            property bool doNotDisturb: root.defaults.doNotDisturb
            property bool nightLight: root.defaults.nightLight
            property int nightLightTemperature: root.defaults.nightLightTemperature
            property var emojiRecent: root.defaults.emojiRecent
            property string emojiSkinTone: root.defaults.emojiSkinTone
        }
    }

    Timer {
        id: stateSaveTimer
        interval: 400
        onTriggered: stateMkdir.running = true
    }

    Process {
        id: stateMkdir
        command: ["mkdir", "-p", root.stateDir]
        onExited: stateFile.writeAdapter()
    }
}
