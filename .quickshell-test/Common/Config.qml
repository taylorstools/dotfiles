pragma Singleton

import QtQuick
import Quickshell

// Settings that DMS kept in settings.json / plugin_settings.json. Edit here;
// Quickshell reloads the shell as soon as you save.
Singleton {
    // Bar
    readonly property real barTransparency: 0.8     // DMS popupTransparency (bar follows it)
    readonly property real popupTransparency: 0.8
    readonly property bool blur: true               // compositor blur behind the bar and launcher
    readonly property bool collapseTray: true       // every tray icon behind the chevron, like your dms.nix patch

    // Better Running Apps (values copied from plugin_settings.json)
    readonly property var betterRunningApps: ({
            "maxWidthPercent": 100,
            "minTitleWidth": 32,
            "maxRunningAppsWidth": 0,
            "fullTitleWidth": 120,
            "currentWorkspaceOnly": false,
            "groupByApp": false,
            "largeIcons": true,
            "reservedBarWidth": 300
        })

    // Better Clock (DMS clock settings)
    readonly property bool use24HourClock: false
    readonly property bool showSeconds: false
    readonly property bool padHours12Hour: false
    readonly property bool clockCompactMode: false
    readonly property string clockDateFormat: "M/d/yyyy"

    // Launcher
    readonly property real launcherWidth: 560
    readonly property int launcherVisibleRows: 8
}
