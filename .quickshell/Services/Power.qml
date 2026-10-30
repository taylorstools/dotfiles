pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// Lock / sleep / restart / shut down, using the commands from the settings
// window. They run right away with no confirmation, like the Windows power menu.
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
}
