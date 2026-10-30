import QtQuick
import Quickshell
import qs.Common

// A popup beside a dock icon, on the side away from the screen edge. Used for
// the dock's tooltips and right-click menu.
PopupWindow {
    id: root

    required property Item target
    // Which side of the screen the dock is on: "left" or "right".
    property string side: "left"
    property real gap: Theme.spacingS
    property real padding: Theme.spacingS
    default property alias content: body.data

    anchor.item: target
    anchor.rect.x: side === "left" ? (target ? target.width : 0) + gap : -gap
    anchor.rect.y: 0
    anchor.rect.width: 0
    anchor.rect.height: target ? target.height : 0
    anchor.edges: side === "left" ? Edges.Right : Edges.Left
    anchor.gravity: side === "left" ? Edges.Right : Edges.Left

    implicitWidth: body.childrenRect.width + padding * 2
    implicitHeight: body.childrenRect.height + padding * 2
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
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
