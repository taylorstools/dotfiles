//@ pragma UseQApplication
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1

// Test Quickshell config. Start it with ./run.sh; it runs alongside DMS and
// touches nothing else. Quickshell reloads automatically when you save a file.

import QtQuick
import Quickshell
import qs.Bar
import qs.Launcher
import qs.Notepad

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Launcher {}
    Notepad {}
}
