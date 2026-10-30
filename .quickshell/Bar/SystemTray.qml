import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common
import qs.Widgets

// Windows-style tray: with Config.collapseTray every icon lives behind the
// chevron, in the tray flyout (Bar/TrayFlyout.qml), which opens and closes
// like the other bar flyouts; otherwise icons sit on the bar.
Item {
    id: root

    property real barThickness: Theme.barThickness

    readonly property var items: SystemTray.items.values
    readonly property real iconSize: Theme.barIconSize(barThickness, false)
    // Tray icon size; the widget adds the usual bar padding around it.
    readonly property real itemSize: iconSize + Theme.spacingXS + Theme.spacingXXS
    readonly property var screen: QsWindow.window?.screen ?? null
    readonly property bool open: Popouts.trayScreen !== null && Popouts.trayScreen === screen

    implicitWidth: items.length === 0 ? 0 : (Config.collapseTray ? chevron.width : inlineRow.implicitWidth)
    implicitHeight: barThickness
    visible: items.length > 0

    // Collapsed: the chevron opens the tray flyout.

    Item {
        id: chevron
        visible: Config.collapseTray
        width: root.itemSize + Theme.widgetPadding * 2
        height: root.barThickness
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            color: chevronMouse.containsMouse || root.open ? Theme.widgetHover : "transparent"
        }

        MaterialIcon {
            anchors.centerIn: parent
            // Caret glyphs for a tray in the bar's right section.
            name: root.open ? "keyboard_arrow_down" : "keyboard_arrow_up"
            size: root.iconSize
        }

        MouseArea {
            id: chevronMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Popouts.toggleTray(root.screen, chevron.mapToItem(null, chevron.width / 2, 0).x)
        }
    }

    // Expanded: icons straight on the bar.

    Row {
        id: inlineRow
        visible: !Config.collapseTray
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: Config.collapseTray ? [] : root.items

            delegate: TrayIcon {
                iconSize: root.iconSize
                menuWindow: root.QsWindow.window
            }
        }
    }
}
