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
    property string clockTab: "overview"
    property bool settingsOpen: false

    // Opening one flyout closes the others.
    function toggleControlCenter(screen) {
        clockScreen = null;
        batteryScreen = null;
        controlCenterScreen = controlCenterScreen === screen ? null : screen;
    }

    function toggleClock(screen) {
        controlCenterScreen = null;
        batteryScreen = null;
        clockScreen = clockScreen === screen ? null : screen;
    }

    function toggleBattery(screen) {
        controlCenterScreen = null;
        clockScreen = null;
        batteryScreen = batteryScreen === screen ? null : screen;
    }

    function closeFlyouts() {
        controlCenterScreen = null;
        clockScreen = null;
        batteryScreen = null;
    }
}
