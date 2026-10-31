import QtQuick
import qs.Common

// The line under a panel's text input (launcher, runner, clipboard, window
// switcher): the input sits on the panel's own background, marked by a 2px
// primary line along its bottom. Put it inside the input's box.
Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Theme.spacingXS
    anchors.rightMargin: Theme.spacingXS
    // 2px, snapped to whole screen pixels so it stays crisp.
    height: Theme.snap(2)
    radius: height / 2
    color: Theme.primary
}
