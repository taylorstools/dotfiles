import QtQuick
import Quickshell
import qs.Common

// A popup that opens just above a bar item. Put the contents inside; the
// popup sizes itself to them. Used for tooltips, the tray and context menus.
PopupWindow {
    id: root

    required property Item target
    property real gap: Theme.spacingXS
    property real padding: Theme.spacingS
    property real radius: Theme.cornerRadius
    default property alias content: body.data

    anchor.item: target
    anchor.rect.x: 0
    anchor.rect.y: -gap
    anchor.rect.width: target ? target.width : 0
    anchor.rect.height: 0
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    implicitWidth: body.childrenRect.width + padding * 2
    implicitHeight: body.childrenRect.height + padding * 2
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.popupBackground
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.25)
    }

    Item {
        id: body
        x: root.padding
        y: root.padding
        width: childrenRect.width
        height: childrenRect.height
    }
}
