pragma Singleton

import QtQuick
import Quickshell

// Which popouts are open, so the bar (one per screen) can open things that
// live once in shell.qml.
Singleton {
    id: root

    // The screen the control center is open on, or null when it's closed.
    property var controlCenterScreen: null
    // Same for the clock flyout, plus which of its tabs is showing.
    property var clockScreen: null
    // Same for the battery flyout.
    property var batteryScreen: null
    // Same for the tray flyout, plus the chevron's x on that screen (the
    // flyout opens above it).
    property var trayScreen: null
    property real trayX: 0
    property string clockTab: "overview"
    property bool settingsOpen: false
    // The right-click menu (Bar/ContextMenu.qml): its screen (null when
    // closed), the point it's placed against on that screen, which way it
    // opens from there ("top", "left" or "right"), and its rows.
    property var contextMenuScreen: null
    property real contextMenuX: 0
    property real contextMenuY: 0
    property string contextMenuSide: "top"
    property var contextMenuItems: []

    readonly property bool flyoutOpen: controlCenterScreen !== null || clockScreen !== null || batteryScreen !== null || trayScreen !== null

    // Floating above the taskbar, centred on x.
    // items: a list of { icon: material icon, text, action: function }. A row
    // with no action is a label, and icon is optional.
    function openContextMenuAboveBar(screen, x, items) {
        openContextMenu(screen, "top", x, screen.height - Theme.barThickness - Theme.spacingS, items);
    }

    // Opening from (x, y) towards side ("left" or "right"), centred on y.
    function openContextMenuBeside(screen, side, x, y, items) {
        openContextMenu(screen, side, x, y, items);
    }

    function openContextMenu(screen, side, x, y, items) {
        contextMenuSide = side;
        contextMenuX = x;
        contextMenuY = y;
        contextMenuItems = items;
        contextMenuScreen = screen;
    }

    // Leaves the rows in place: they're still showing while the menu fades out.
    function closeContextMenu() {
        contextMenuScreen = null;
    }

    // Opening one flyout closes the others.
    function toggleControlCenter(screen) {
        clockScreen = null;
        batteryScreen = null;
        trayScreen = null;
        controlCenterScreen = controlCenterScreen === screen ? null : screen;
    }

    function toggleClock(screen) {
        controlCenterScreen = null;
        batteryScreen = null;
        trayScreen = null;
        clockScreen = clockScreen === screen ? null : screen;
    }

    function toggleBattery(screen) {
        controlCenterScreen = null;
        clockScreen = null;
        trayScreen = null;
        batteryScreen = batteryScreen === screen ? null : screen;
    }

    function toggleTray(screen, x) {
        controlCenterScreen = null;
        clockScreen = null;
        batteryScreen = null;
        trayX = x;
        trayScreen = trayScreen === screen ? null : screen;
    }

    function closeFlyouts() {
        trayScreen = null;
        controlCenterScreen = null;
        clockScreen = null;
        batteryScreen = null;
    }

    // The power menu (PowerMenu/PowerMenu.qml) opens on this.
    signal powerMenuRequested
}
