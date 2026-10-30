import QtQuick
import qs.Common

// Open/close timing for a panel window. Bind `shown`; animate the panel with
// `progress` (0 closed, 1 open) and use `mapped` as the window's `visible`, so
// the window stays up until the closing animation has finished. With the
// animation duration at 0 everything just switches.
Item {
    id: root

    property bool shown: false
    property real progress: shown ? 1 : 0
    readonly property bool mapped: shown || progress > 0

    Behavior on progress {
        NumberAnimation {
            duration: Theme.animDuration
            easing.type: Easing.OutCubic
        }
    }
}
