import QtQuick
import Quickshell
import qs.Common

// Hover tooltip above an item (below it at the top of the screen):
//   Tooltip { target: someItem; text: "..."; shown: hovered }
// It lets the pointer through, so it can never take the hover from its own
// target (which made tooltips flicker when they ended up over it).
Item {
    id: root

    required property Item target
    property string text: ""
    property bool shown: false

    Loader {
        active: root.shown && root.text !== ""
        sourceComponent: BarPopup {
            target: root.target
            padding: Theme.spacingS
            radius: Theme.cornerRadius / 2
            visible: true
            mask: Region {}

            StyledText {
                text: root.text
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
