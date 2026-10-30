import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Bottom bar:
//   left:  workspace switcher, Better Running Apps
//   right: system tray, battery, network/bluetooth/volume, Better Clock
PanelWindow {
    id: bar

    required property var modelData

    screen: modelData
    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Theme.barThickness
    color: "transparent"

    WlrLayershell.namespace: "qstest:bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
        anchors.fill: parent
        color: Theme.barBackground
    }

    // Compositor blur behind the bar (ext-background-effect, needs a recent
    // Quickshell). Set from JS so an older Quickshell just skips it instead of
    // failing to load.
    Item {
        Region {
            id: blurRegion
            width: bar.width
            height: bar.height
        }
    }

    // Re-apply when blur is switched in the settings window.
    Connections {
        target: Settings
        function onBlurChanged() {
            bar.applyBlur();
        }
    }

    function applyBlur() {
        if (bar.BackgroundEffect !== undefined)
            bar.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
    }

    Component.onCompleted: applyBlur()
    onVisibleChanged: applyBlur()

    // Scrolling on empty bar space switches workspaces.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real accumulator: 0
        onWheel: wheel => {
            accumulator += wheel.angleDelta.y;
            if (Math.abs(accumulator) >= 120) {
                Niri.focusWorkspaceRelative(accumulator < 0 ? 1 : -1);
                accumulator = 0;
            }
        }
    }

    Row {
        id: leftSection
        anchors.left: parent.left
        // Measured: the switcher sits 1 physical px further in, and its
        // running apps start 2 px closer to the switcher.
        anchors.leftMargin: Theme.barEdgeMargin + 1 / Theme.dpr
        anchors.verticalCenter: parent.verticalCenter
        // Bar spacing 0: widgets sit edge to edge, their padding is the gap.
        spacing: -2 / Theme.dpr

        WorkspaceSwitcher {
            id: workspaces
            anchors.verticalCenter: parent.verticalCenter
            screenName: bar.screen ? bar.screen.name : ""
        }

        BetterRunningApps {
            anchors.verticalCenter: parent.verticalCenter
            parentScreen: bar.screen
            barThickness: Theme.barThickness
            // Whatever the bar has left between the switcher and the right side.
            allottedPrimarySize: bar.width - leftSection.anchors.leftMargin - workspaces.width - leftSection.spacing - rightSection.width - rightSection.anchors.rightMargin - Theme.spacingS
        }
    }

    Row {
        id: rightSection
        anchors.right: parent.right
        // 1 physical px nearer the edge than the margin, measured.
        anchors.rightMargin: Theme.barEdgeMargin - 1 / Theme.dpr
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        // The gaps between these widgets were measured against Taylor's old bar on
        // this screen (in physical pixels), since they don't follow one rule.
        SystemTray {
            anchors.verticalCenter: parent.verticalCenter
        }

        Gap {
            pixels: 3
        }

        Battery {
            id: battery
            anchors.verticalCenter: parent.verticalCenter
            parentScreen: bar.screen
        }

        Gap {
            pixels: 1
        }

        StatusIcons {
            id: statusIcons
            anchors.verticalCenter: parent.verticalCenter
            parentScreen: bar.screen
        }

        Gap {
            pixels: 6
        }

        BetterClock {
            id: clock
            anchors.verticalCenter: parent.verticalCenter
            active: Popouts.clockScreen !== null && Popouts.clockScreen === bar.screen
            onClockClicked: Popouts.toggleClock(bar.screen)
        }
    }

    // A press anywhere on the bar closes the control center, calendar or
    // battery flyout, except on the status icons, the clock and the battery,
    // which toggle their own. A PointHandler only watches (a passive grab):
    // the press, scrolling, hover and each widget's hand cursor all go on to
    // the widget underneath. (A MouseArea here hid every widget's cursor.)
    Item {
        id: closer

        function over(item, position) {
            return item.contains(item.mapFromItem(closer, position.x, position.y));
        }

        anchors.fill: parent
        z: 100

        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: {
                if (!active)
                    return;
                const p = point.position;
                if (!closer.over(statusIcons, p) && !closer.over(clock, p) && !closer.over(battery, p))
                    Popouts.closeFlyouts();
            }
        }
    }

    component Gap: Item {
        property real pixels: 0

        width: pixels / Theme.dpr
        height: 1
    }
}
