pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// Lock / log out / sleep / restart / shut down / reboot into Windows, using
// the commands from the settings window (Power page). They run right away
// with no confirmation, like the Windows power menu.
Singleton {
    function run(command) {
        if (command.trim() !== "")
            Quickshell.execDetached(["sh", "-c", command]);
    }

    function lock() {
        run(Settings.lockCommand);
    }
    function sleep() {
        run(Settings.sleepCommand);
    }
    function restart() {
        run(Settings.restartCommand);
    }
    function shutdown() {
        run(Settings.shutdownCommand);
    }
    function logout() {
        run(Settings.logoutCommand);
    }
    function windows() {
        run(Settings.windowsCommand);
    }
}
