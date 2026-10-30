import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// The wallpaper on one screen, on niri's background layer. A new wallpaper
// fades in over the old one once it has loaded.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.surface

    WlrLayershell.namespace: "qstest:wallpaper"
    WlrLayershell.layer: WlrLayer.Background

    // Decode at the screen's pixel size instead of the image's.
    readonly property size decodeSize: Qt.size(width * (screen?.devicePixelRatio ?? 1), height * (screen?.devicePixelRatio ?? 1))
    readonly property string source: Wallpaper.path ? "file://" + Wallpaper.path : ""

    onSourceChanged: {
        if (current.source.toString() === source)
            return;
        previous.source = current.source;
        current.opacity = 0;
        current.source = source;
    }

    Image {
        id: previous
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: root.decodeSize
        asynchronous: true
    }

    Image {
        id: current
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: root.decodeSize
        asynchronous: true
        source: root.source

        onStatusChanged: {
            if (status === Image.Ready && opacity < 1)
                fadeIn.restart();
        }

        NumberAnimation {
            id: fadeIn
            target: current
            property: "opacity"
            to: 1
            // Its own setting, on the Wallpaper page.
            duration: Math.max(0, Number(Settings.wallpaperFadeDuration) || 0)
            easing.type: Easing.InOutQuad
            onFinished: previous.source = ""
        }
    }
}
