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
Singleton {
    id: root

    readonly property string path: Settings.wallpaperPath
    // Images in the wallpaper folder, sorted by name.
    property var images: []
    property bool generating: false
    property string lastError: ""

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

    function generateColors() {
        if (generator.running) {
            regenerate.restart();
            return;
        }
        generating = true;
        generator.running = true;
    }

    onPathChanged: regenerate.restart()
    Component.onCompleted: rescanFolder()

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

    // Coalesces the startup load and quick clicks through the picker.
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
        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) | sort', "sh", Settings.wallpaperFolder]
        stdout: StdioCollector {
            onStreamFinished: root.images = text.trim().split("\n").filter(l => l)
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
