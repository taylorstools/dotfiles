//@ pragma UseQApplication
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1

// Taylor's desktop shell. It runs as quickshell.service; ./run.sh runs it by
// hand with errors in the terminal. Quickshell reloads when you save a file.

import QtQuick
import Quickshell
import qs.Bar
import qs.Battery
import qs.Clipboard
import qs.Clock
import qs.ControlCenter
import qs.Dock
import qs.Launcher
import qs.Notepad
import qs.Notifications
import qs.Osd
import qs.Polkit
import qs.Runner
import qs.Services
import qs.Settings
import qs.Switcher
import qs.Wallpaper
import qs.Whisrs

ShellRoot {
    // Blur strength reaches niri through a file, and clipboard history has to
    // be watching from the start; touching both singletons starts them.
    Component.onCompleted: {
        NiriBlur.ensureWritten();
        void ClipboardHistory.loaded;
        void NightLight.enabled;
    }

    Variants {
        model: Quickshell.screens

        Background {}
    }

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        Dock {}
    }

    Launcher {}
    Runner {}
    WindowSwitcher {}
    ClipboardPanel {}
    Notepad {}
    ControlCenter {}
    ClockFlyout {}
    BatteryFlyout {}
    Popups {}
    Osd {}
    PolkitDialog {}
    WhisrsPill {}
    SettingsWindow {}
}
