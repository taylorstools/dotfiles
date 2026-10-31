import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// A 1x1 invisible layer window, namespace "qstest:ready", that appears once
// the wallpaper has been drawn. The niri login splash (nixos
// modules/components/niri-splash, myOptions.niri-splash.namespaces) waits
// for it and the bar, so it lifts onto a finished desktop.
PanelWindow {
    visible: Wallpaper.shown
    anchors {
        top: true
        left: true
    }
    implicitWidth: 1
    implicitHeight: 1
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "qstest:ready"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
}
