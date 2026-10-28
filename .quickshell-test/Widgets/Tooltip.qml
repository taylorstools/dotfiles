import QtQuick
import qs.Common

// Hover tooltip above a bar item: Tooltip { target: someItem; text: "..."; shown: hovered }
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

            StyledText {
                text: root.text
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
