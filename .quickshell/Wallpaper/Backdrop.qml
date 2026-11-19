import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Widgets

// The blurred, darkened wallpaper behind niri's overview, where swaybg used
// to show the effects wallpaper. niri places it within the backdrop by its
// namespace (dot_config/niri/custom/rules.kdl), so it's never seen outside
// the overview: the backdrop is the bottom of the stack, under the desktop's
// own wallpaper (Background.qml). Also keeps the picture decoded for the lock
// screen and power menu, which ask for the same one (Qt's image cache).
PanelWindow {
    required property var modelData

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    WlrLayershell.namespace: "qstest:backdrop"
    WlrLayershell.layer: WlrLayer.Background

    BlurredWallpaper {
        anchors.fill: parent
    }
}
