import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Bottom bar, laid out like your DMS bar config:
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

    function applyBlur() {
        if (bar.BackgroundEffect !== undefined)
            bar.BackgroundEffect.blurRegion = Config.blur ? blurRegion : null;
    }

    Component.onCompleted: applyBlur()
    onVisibleChanged: applyBlur()

    // Scrolling on empty bar space switches workspaces (DMS scrollYBehavior).
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
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

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
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        SystemTray {
            anchors.verticalCenter: parent.verticalCenter
        }

        Battery {
            anchors.verticalCenter: parent.verticalCenter
        }

        StatusIcons {
            anchors.verticalCenter: parent.verticalCenter
        }

        BetterClock {
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
