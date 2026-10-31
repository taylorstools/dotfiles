pragma Singleton

import QtQuick
import Quickshell

// Fixed settings that have no place in the settings window yet. Edit here;
// Quickshell reloads the shell as soon as you save.
Singleton {
    // Bar
    // Opacity and blur moved to the settings window (Settings.surfaceOpacity,
    // Settings.blur, Settings.blurStrength).
    readonly property bool collapseTray: true       // every tray icon behind the chevron, Windows-style

    // Better Running Apps moved to the settings window (Settings.runningApps*).

    // Better Clock
    readonly property bool use24HourClock: false
    readonly property bool showSeconds: false
    readonly property bool padHours12Hour: false
    readonly property bool clockCompactMode: false
    readonly property string clockDateFormat: "M/d/yyyy"

    // Launcher
    readonly property real launcherWidth: 560
    readonly property int launcherVisibleRows: 8

    // OSD (volume / brightness / mic)
    readonly property real osdWidth: 280
    // Toasts share the OSD's pill and spot; they stay up longer and grow to
    // fit their text, up to this width.
    readonly property int toastDuration: 3000
    readonly property real toastMaxWidth: 560

    // Runner
    readonly property real runnerWidth: 720
    readonly property int runnerVisibleRows: 12

    // Window switcher (Mod+Tab)
    readonly property real switcherWidth: 720
    readonly property int switcherVisibleRows: 10

    // Control center
    readonly property real controlCenterWidth: 400
    readonly property int controlCenterListRows: 8     // Wi-Fi / Bluetooth list height, in whole rows

    // Clock flyout and notifications
    readonly property real clockFlyoutWidth: 400
    readonly property real clockFlyoutHeight: 540
    readonly property real batteryFlyoutWidth: 380
    readonly property real notificationPopupWidth: 360
    readonly property int notificationMaxPopups: 4

    // Notepad
    readonly property real notepadWidth: 480
    readonly property real notepadExpandedWidth: 960
    readonly property real notepadEdgeGap: 4        // gap to the screen edge and the bar
    readonly property real notepadFontSize: 14
}
