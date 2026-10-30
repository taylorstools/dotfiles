import QtQuick
import Quickshell.Widgets
import qs.Common

// One tray item: left click activates, right click opens the app's menu,
// middle click is the secondary action, scrolling scrolls. Used on the bar
// (tray not collapsed) and in the tray flyout. `menuWindow` is the window
// the app's menu opens from; `activated` fires after a left-click activate.
Item {
    id: root

    required property var modelData
    property var menuWindow: null
    property real iconSize: 16

    signal activated

    width: iconSize + Theme.spacingS
    height: iconSize + Theme.spacingS

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius / 2
        color: mouse.containsMouse ? Theme.widgetHover : "transparent"
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: root.iconSize
        source: root.modelData.icon
        asynchronous: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            const item = root.modelData;
            if (event.button === Qt.MiddleButton) {
                item.secondaryActivate();
            } else if (event.button === Qt.RightButton || item.onlyMenu) {
                if (item.hasMenu && root.menuWindow) {
                    const p = root.mapToItem(null, 0, 0);
                    item.display(root.menuWindow, p.x, p.y);
                }
            } else {
                item.activate();
                root.activated();
            }
        }
        onWheel: wheel => root.modelData.scroll(wheel.angleDelta.y / 120, false)
    }
}
