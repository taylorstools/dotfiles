import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// The dock: a vertical strip on the left
// (or right), pinned apps first, a dot per open window beside the icon that
// stretches for the focused app. Settings live on the settings window's Dock
// page.
//   click        launch, or focus (click again to step through its windows)
//   middle click open a new window
//   right click  new window, pin/unpin, close
// With auto-hide on it slides out of view and comes back when the pointer
// reaches its edge of the screen, and while niri's overview is open.
PanelWindow {
    id: root

    required property var modelData

    readonly property bool onLeft: Settings.dockPosition !== "right"
    readonly property real iconSize: Settings.dockIconSize
    readonly property real spacing: Settings.dockSpacing
    readonly property real border: Settings.dockBorder ? 1 : 0
    readonly property real dockWidth: iconSize + spacing * 2

    // The app whose right-click menu is open, or "".
    property string menuApp: ""
    property Item menuAnchor: null
    property bool hovering: false
    readonly property bool revealed: !Settings.dockAutoHide || hovering || menuApp !== "" || Niri.overviewOpen

    screen: modelData
    visible: Settings.dockEnabled
    anchors {
        top: true
        bottom: true
        left: onLeft
        right: !onLeft
    }
    implicitWidth: dockWidth + border * 2 + Theme.spacingS
    // Without auto-hide the dock keeps its space, like a bar.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Settings.dockAutoHide ? 0 : dockWidth + border * 2
    color: "transparent"

    // Only the dock itself takes input; while hidden, a thin strip along the
    // screen edge (the height of the dock) brings it back.
    mask: Region {
        item: root.revealed ? panel : edgeTrigger
    }

    WlrLayershell.namespace: "qstest:dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Compositor blur behind the dock (needs a recent Quickshell).
    Item {
        Region {
            id: blurRegion
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
        }
    }

    function applyBlur() {
        // Region.radius only exists in newer Quickshell builds.
        if ("radius" in blurRegion)
            blurRegion.radius = panel.radius;
        if (root.BackgroundEffect !== undefined)
            root.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
    }

    Component.onCompleted: applyBlur()
    onVisibleChanged: applyBlur()

    Connections {
        target: Settings
        function onBlurChanged() {
            root.applyBlur();
        }
    }

    Item {
        id: edgeTrigger
        x: root.onLeft ? 0 : parent.width - width
        y: panel.y
        width: 2
        height: panel.height
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideDelay.stop();
                root.hovering = true;
            } else {
                hideDelay.restart();
            }
        }
    }

    Timer {
        id: hideDelay
        interval: 400
        onTriggered: root.hovering = false
    }

    Rectangle {
        id: panel

        readonly property real shownX: root.onLeft ? root.border : root.width - width - root.border
        readonly property real hiddenX: root.onLeft ? -width - root.border * 2 : root.width + root.border

        x: root.revealed ? shownX : hiddenX
        anchors.verticalCenter: parent.verticalCenter
        width: root.dockWidth
        height: column.implicitHeight + root.spacing * 2
        radius: Theme.cornerRadius
        color: Theme.barBackground
        // The Dock page's Border toggle turns it on; its colour is the panel
        // border from Settings > Appearance.
        border.width: root.border
        border.color: Theme.blurBorder

        Behavior on x {
            NumberAnimation {
                duration: Theme.animDuration
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: column

            x: root.spacing
            y: root.spacing
            spacing: root.spacing

            Repeater {
                // Keyed by app id, so delegates (and their hover state) survive
                // windows opening and closing.
                model: ScriptModel {
                    values: DockApps.ids
                }

                delegate: Item {
                    id: app

                    required property string modelData
                    readonly property var item: DockApps.items[modelData] ?? null
                    readonly property var windows: item?.windows ?? []
                    readonly property bool focused: windows.some(w => w.id === Niri.focusedWindowId)
                    readonly property string name: Apps.nameFor(modelData)

                    width: root.iconSize
                    height: root.iconSize

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.iconSize + 6
                        height: root.iconSize + 6
                        radius: Theme.cornerRadius / 1.5
                        color: appMouse.containsMouse || root.menuApp === app.modelData ? Theme.widgetHover : "transparent"
                    }

                    IconImage {
                        id: icon
                        anchors.fill: parent
                        source: Apps.iconFor(app.modelData)
                        asynchronous: true
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: icon.status !== Image.Ready
                        name: "apps"
                        size: root.iconSize * 0.8
                        color: Theme.surfaceVariantText
                    }

                    // Running dots in the padding between the icon and the
                    // screen edge, as circles.
                    Column {
                        readonly property real dot: Math.max(4, root.iconSize * 0.1)

                        x: root.onLeft ? -(root.spacing + dot) / 2 : root.iconSize + (root.spacing - dot) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXXS

                        Repeater {
                            model: Math.min(app.windows.length, 3)

                            delegate: Rectangle {
                                required property int index
                                readonly property real dot: Math.max(4, root.iconSize * 0.1)

                                width: dot
                                height: app.focused && index === 0 ? dot * 3 : dot
                                radius: dot / 2
                                color: app.focused && index === 0 ? Theme.primary : Theme.surfaceVariantText

                                Behavior on height {
                                    NumberAnimation {
                                        duration: Theme.animShort
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        anchors.margins: -root.spacing / 2
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.menuAnchor = app;
                                root.menuApp = app.modelData;
                                menuLeave.restart();
                            } else if (mouse.button === Qt.MiddleButton) {
                                DockApps.launch(app.modelData);
                            } else {
                                root.menuApp = "";
                                DockApps.activate(app.modelData);
                            }
                        }
                    }

                    LazyLoader {
                        active: appMouse.containsMouse && root.menuApp === "" && root.revealed

                        DockPopup {
                            target: app
                            side: root.onLeft ? "left" : "right"
                            padding: Theme.spacingS
                            visible: true

                            StyledText {
                                text: app.name
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }

    // Right-click menu. Like the taskbar's, it closes itself once the
    // pointer has been off it for a moment.
    Timer {
        id: menuLeave
        interval: 1500
        onTriggered: {
            if (!menuHover.hovered)
                root.menuApp = "";
        }
    }

    LazyLoader {
        active: root.menuApp !== "" && root.menuAnchor !== null

        DockPopup {
            target: root.menuAnchor
            side: root.onLeft ? "left" : "right"
            padding: Theme.spacingXS
            visible: true

            Column {
                id: menu

                readonly property var item: DockApps.items[root.menuApp] ?? null
                readonly property int windowCount: item?.windows.length ?? 0

                width: 180

                HoverHandler {
                    id: menuHover
                    onHoveredChanged: {
                        if (!hovered)
                            menuLeave.restart();
                    }
                }

                StyledText {
                    width: parent.width
                    leftPadding: Theme.spacingS
                    topPadding: Theme.spacingXS
                    bottomPadding: Theme.spacingXS
                    text: Apps.nameFor(root.menuApp)
                    color: Theme.outline
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }

                // Each closes the menu after acting; that destroys the item.
                MenuItem {
                    icon: "add"
                    text: "New window"
                    onClicked: {
                        DockApps.launch(root.menuApp);
                        root.menuApp = "";
                    }
                }
                MenuItem {
                    icon: DockApps.isPinned(root.menuApp) ? "keep_off" : "keep"
                    text: DockApps.isPinned(root.menuApp) ? "Unpin from dock" : "Pin to dock"
                    onClicked: {
                        DockApps.togglePin(root.menuApp);
                        root.menuApp = "";
                    }
                }
                MenuItem {
                    visible: menu.windowCount > 0
                    icon: "close"
                    text: menu.windowCount > 1 ? "Close " + menu.windowCount + " windows" : "Close"
                    onClicked: {
                        DockApps.closeAll(root.menuApp);
                        root.menuApp = "";
                    }
                }
            }
        }
    }

    component MenuItem: Rectangle {
        id: menuItem

        property string icon
        property string text

        signal clicked

        width: 180
        height: visible ? 32 : 0
        radius: Theme.cornerRadius - Theme.spacingXS
        color: itemMouse.containsMouse ? Theme.widgetHover : "transparent"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: menuItem.icon
                size: 16
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: menuItem.text
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuItem.clicked()
        }
    }
}
