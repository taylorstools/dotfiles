import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services

// X-ray blur, drawn by the shell: the wallpaper, blurred, lined up with the
// wallpaper on screen, under a panel's translucent colour. niri's own x-ray
// does the same but with jagged corners, so NiriBlur leaves it off for the
// shell's surfaces and they use this instead.
//
// It also keeps flyouts the bar's colour: maximized windows stop at the
// bar, so the bar only ever blurs the wallpaper, and a flyout that blurred
// the window behind it came out grey next to it.
//
// A child of the panel, under its colour (z -1), so it shares the panel's
// shape, opacity, scale and slide. The panel is assumed to sit straight in
// its window (panelX/panelY otherwise, as the notification cards do); a
// slide done with a Translate goes in slideX/slideY. The window should drop
// niri's blur while this is active: it would only blur what this covers.
ClippingRectangle {
    id: root

    required property var window
    readonly property Item panel: parent
    property real panelX: panel.x
    property real panelY: panel.y
    property real slideX: 0
    property real slideY: 0

    readonly property bool active: Settings.blur && Settings.blurXray && Wallpaper.path !== ""

    readonly property real screenWidth: window.screen?.width ?? window.width
    readonly property real screenHeight: window.screen?.height ?? window.height
    // Where the window sits on its screen, from its anchors. The shell's only
    // exclusive zones are the bar's (bottom) and the dock's (left), and
    // nothing anchored only to the left but the dock itself, so only a
    // bottom-anchored window that keeps clear of exclusive zones (the OSD)
    // has to allow for one.
    readonly property real windowX: {
        if (window.anchors.right)
            return screenWidth - window.margins.right - window.width;
        if (window.anchors.left)
            return window.margins.left;
        return (screenWidth - window.width) / 2;
    }
    readonly property real windowY: {
        if (window.anchors.top)
            return window.margins.top;
        if (window.anchors.bottom) {
            const bar = window.exclusionMode === ExclusionMode.Normal ? Theme.barThickness : 0;
            return screenHeight - window.margins.bottom - window.height - bar;
        }
        return (screenHeight - window.height) / 2;
    }

    anchors.fill: parent
    z: -1
    visible: active
    radius: panel.radius ?? 0
    // Until the picture has loaded.
    color: Theme.surface

    // The whole screen at a quarter of its size, scaled back up: a quarter of
    // the pixels to blur, and the scale-up smooths it further. Placed against
    // the panel's scale (about its centre) and slide, so it stays put on
    // screen while the panel grows or rises.
    Item {
        readonly property real panelScale: root.panel.scale || 1

        x: root.width / 2 + (-root.windowX - root.panelX - root.width / 2 - root.slideX) / panelScale
        y: root.height / 2 + (-root.windowY - root.panelY - root.height / 2 - root.slideY) / panelScale
        width: root.screenWidth / 4
        height: root.screenHeight / 4
        scale: 4 / panelScale
        transformOrigin: Item.TopLeft

        Image {
            id: picture
            anchors.fill: parent
            visible: false
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width, height)
            asynchronous: true
            // Keeps the old wallpaper up while the picker's new one loads.
            retainWhileLoading: true
            source: root.active ? "file://" + Wallpaper.path : ""
        }

        MultiEffect {
            anchors.fill: parent
            source: picture
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            // Follows the strength slider (niri's own blur, 0 = its default).
            blurMax: Settings.blurStrength > 0 ? Math.max(2, Math.round(Settings.blurStrength * 0.32)) : 16
        }
    }

    // Qt doesn't paint a Rectangle's colour under its border, so a
    // see-through border (Border opacity) showed the bare wallpaper as a
    // bright ring. Tint the ring like the rest of the panel.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.panel.border?.width ?? 0
        border.color: root.panel.color ?? "transparent"
    }
}
