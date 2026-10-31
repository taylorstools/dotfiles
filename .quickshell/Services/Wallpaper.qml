pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// The wallpaper and the colors made from it. Setting a wallpaper saves it to
// settings.json and reruns Theming/generate.sh, which writes
// ~/.cache/qstest/colors.json (Theme watches it, so the whole shell
// recolors) and the app themes (GTK, niri, Ghostty, kitty, KDE, Zed, Firefox).
//   qs ipc -p <this folder> call wallpaper set <path>
//   qs ipc -p <this folder> call wallpaper random     (from Settings.wallpaperFolder)
//   qs ipc -p <this folder> call wallpaper get
// Settings > Wallpaper can also pick a random one at login and every few
// minutes (wallpaperChangeAtStartup, wallpaperAutoChange, ...Interval).
Singleton {
    id: root

    readonly property string path: Settings.wallpaperPath
    // Images in the wallpaper folder, sorted by name.
    property var images: []
    property bool generating: false
    // Set once a screen has drawn the wallpaper (or found nothing to draw),
    // for the login splash (Wallpaper/LoginReady.qml).
    property bool shown: false
    property string lastError: ""

    // At login, while the startup change is being decided: the wallpaper
    // windows hold off drawing, so the login splash lifts onto the new
    // wallpaper rather than the old one fading over to it.
    property bool startupPending: false
    property string listedFolder: ""
    // A marker per niri session (its socket names its pid): there on a config
    // reload or a shell restart, missing at a new login.
    readonly property string sessionMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qstest-wallpaper-session." + (Quickshell.env("NIRI_SOCKET") || "none").split("/").pop()

    readonly property var schemes: ["scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad", "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-tonal-spot", "scheme-vibrant"]

    function set(path) {
        if (path && path !== Settings.wallpaperPath)
            Settings.wallpaperPath = path;
    }

    // Any other image from the folder.
    function random() {
        const others = images.filter(p => p !== path);
        if (others.length > 0)
            set(others[Math.floor(Math.random() * others.length)]);
    }

    function rescanFolder() {
        if (!lister.running)
            lister.running = true;
    }

    // Not before settings.json is read (the wallpaper would still be the
    // default) or while the login wallpaper is being picked: either would
    // theme every app for a wallpaper that's about to change.
    function generateColors() {
        if (!Settings.ready || startupPending)
            return;
        if (generator.running) {
            regenerate.restart();
            return;
        }
        generating = true;
        generator.running = true;
    }

    onPathChanged: regenerate.restart()
    onStartupPendingChanged: regenerate.restart()
    Component.onCompleted: {
        if (sessionMarkerFile.text() === "") {
            Quickshell.execDetached(["sh", "-c", 'echo 1 > "$1"', "sh", sessionMarker]);
            startupPending = true;
            startupTimeout.start();
        }
        rescanFolder();
    }

    // Once settings are read and the folder listed: change it or not, then
    // let the wallpaper windows draw.
    function decideStartup() {
        if (!startupPending || !Settings.ready || listedFolder !== Settings.wallpaperFolder)
            return;
        if (Settings.wallpaperChangeAtStartup)
            random();
        startupPending = false;
        startupTimeout.stop();
    }

    Connections {
        target: Settings
        function onReadyChanged() {
            regenerate.restart();
            root.rescanFolder();
            root.decideStartup();
        }
    }

    FileView {
        id: sessionMarkerFile
        path: root.sessionMarker
        blockLoading: true
        printErrors: false
    }

    // Never keep the wallpaper hidden for long.
    Timer {
        id: startupTimeout
        interval: 3000
        onTriggered: root.startupPending = false
    }

    // Auto-change.
    Timer {
        running: Settings.wallpaperAutoChange
        repeat: true
        interval: Math.max(1, Number(Settings.wallpaperChangeInterval) || 15) * 60000
        onTriggered: root.random()
    }

    Connections {
        target: Settings
        function onMatugenSchemeChanged() {
            regenerate.restart();
        }
        function onColorfulSeedChanged() {
            regenerate.restart();
        }
        function onWallpaperFolderChanged() {
            root.rescanFolder();
        }
    }

    // Coalesces the startup load and quick clicks through the picker. It
    // runs on every reload too; generate.sh skips the work when nothing
    // changed.
    Timer {
        id: regenerate
        interval: 150
        running: true
        onTriggered: root.generateColors()
    }

    // Theming/generate.sh makes the shell's palette and the app themes.
    // matugen asks which colour to build from when an image has several; the
    // seed flags answer it. --source-color-index 0 takes the main colour (the
    // the wallpaper's main colour); --prefer saturation the most colourful one.
    Process {
        id: generator
        command: ["bash", Quickshell.shellDir + "/Theming/generate.sh", root.path || "", Settings.matugenScheme || "scheme-neutral"].concat(Settings.colorfulSeed ? ["--prefer", "saturation"] : ["--source-color-index", "0"])
        stderr: StdioCollector {
            id: generatorErr
        }
        onExited: code => {
            root.generating = false;
            root.lastError = code === 0 ? "" : ("matugen: " + generatorErr.text.trim().split("\n")[0]);
        }
    }

    Process {
        id: lister
        // The folder this listing is of, fixed when it starts.
        property string folder: ""
        onRunningChanged: {
            if (running)
                folder = Settings.wallpaperFolder;
        }
        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) | sort', "sh", Settings.wallpaperFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                root.images = text.trim().split("\n").filter(l => l);
                root.listedFolder = lister.folder;
                root.decideStartup();
            }
        }
    }

    IpcHandler {
        target: "wallpaper"

        function set(path: string): void {
            root.set(path);
        }
        function random(): void {
            root.random();
        }
        function get(): string {
            return root.path;
        }
    }
}
