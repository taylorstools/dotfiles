import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// Windows-style tray: with Config.collapseTray every icon lives behind the
// chevron, Windows-style (Config.collapseTray); otherwise icons sit
// on the bar. Left click activates, right click opens the app's menu,
// middle click is the secondary action.
Item {
    id: root

    property real barThickness: Theme.barThickness
    property bool popupOpen: false

    readonly property var items: SystemTray.items.values
    readonly property real iconSize: Theme.barIconSize(barThickness, false)
    // Tray icon size; the widget adds the usual bar padding around it.
    readonly property real itemSize: iconSize + Theme.spacingXS + Theme.spacingXXS

    implicitWidth: items.length === 0 ? 0 : (Config.collapseTray ? chevron.width : inlineRow.implicitWidth)
    implicitHeight: barThickness
    visible: items.length > 0

    component TrayIcon: Item {
        id: trayIcon

        required property var modelData
        property var menuWindow: null

        width: root.iconSize + Theme.spacingS
        height: root.iconSize + Theme.spacingS

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius / 2
            color: iconMouse.containsMouse ? Theme.widgetHover : "transparent"
        }

        IconImage {
            anchors.centerIn: parent
            implicitSize: root.iconSize
            source: trayIcon.modelData.icon
            asynchronous: true
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                const item = trayIcon.modelData;
                if (mouse.button === Qt.MiddleButton) {
                    item.secondaryActivate();
                } else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                    if (item.hasMenu && trayIcon.menuWindow) {
                        const p = trayIcon.mapToItem(null, 0, 0);
                        item.display(trayIcon.menuWindow, p.x, p.y);
                    }
                } else {
                    item.activate();
                    root.popupOpen = false;
                }
            }
            onWheel: wheel => trayIcon.modelData.scroll(wheel.angleDelta.y / 120, false)
        }
    }

    // Collapsed: chevron + popup grid

    Item {
        id: chevron
        visible: Config.collapseTray
        width: root.itemSize + Theme.widgetPadding * 2
        height: root.barThickness
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            color: chevronMouse.containsMouse || root.popupOpen ? Theme.widgetHover : "transparent"
        }

        MaterialIcon {
            anchors.centerIn: parent
            // Caret glyphs for a tray in the bar's right section.
            name: root.popupOpen ? "keyboard_arrow_down" : "keyboard_arrow_up"
            size: root.iconSize
        }

        MouseArea {
            id: chevronMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.popupOpen = !root.popupOpen
        }
    }

    Loader {
        active: Config.collapseTray && root.popupOpen && root.items.length > 0
        sourceComponent: BarPopup {
            id: trayPopup
            target: chevron
            visible: true

            Grid {
                columns: Math.min(6, root.items.length)
                spacing: Theme.spacingXS

                Repeater {
                    model: root.items

                    delegate: TrayIcon {
                        menuWindow: trayPopup
                    }
                }
            }
        }
    }

    // Expanded: icons straight on the bar

    Row {
        id: inlineRow
        visible: !Config.collapseTray
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: Config.collapseTray ? [] : root.items

            delegate: TrayIcon {
                menuWindow: root.QsWindow.window
            }
        }
    }
}
