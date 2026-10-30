import QtQuick
import qs.Common

// Horizontal 0..1 slider. `value` is shown unless you're dragging; `moved`
// fires with each new value from a drag, click, scroll or key. Clicking it
// (or Tab) gives it focus; then Left/Right (or Down/Up) move one step,
// Page Down/Page Up ten, Home/End to the ends. Set `steps` to how many units
// the setting has across the range, so one key press is one unit.
Item {
    id: root

    property real value: 0
    property int steps: 100
    readonly property bool dragging: mouse.pressed
    property real _dragValue: 0
    readonly property real shownValue: Math.max(0, Math.min(1, dragging ? _dragValue : value))
    readonly property real knobSize: 16

    signal moved(real value)

    implicitHeight: 20
    implicitWidth: 200
    activeFocusOnTab: true

    function step(n) {
        const s = Math.max(1, root.steps);
        root.moved(Math.max(0, Math.min(1, (Math.round(root.value * s) + n) / s)));
    }

    Keys.onPressed: e => {
        switch (e.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            step(-1);
            break;
        case Qt.Key_Right:
        case Qt.Key_Up:
            step(1);
            break;
        case Qt.Key_PageDown:
            step(-10);
            break;
        case Qt.Key_PageUp:
            step(10);
            break;
        case Qt.Key_Home:
            root.moved(0);
            break;
        case Qt.Key_End:
            root.moved(1);
            break;
        default:
            return;
        }
        e.accepted = true;
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.surfaceContainerHighest

        Rectangle {
            width: knob.x + root.knobSize / 2
            height: parent.height
            radius: 3
            color: Theme.primary
        }
    }

    Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        x: root.shownValue * (root.width - root.knobSize)
        width: root.knobSize
        height: root.knobSize
        radius: root.knobSize / 2
        color: Theme.primary
        scale: mouse.containsMouse || root.dragging ? 1.1 : 1
        // A ring while the arrow keys move this slider.
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.surfaceText
    }

    MouseArea {
        id: mouse

        function update(x) {
            root._dragValue = Math.max(0, Math.min(1, (x - root.knobSize / 2) / (root.width - root.knobSize)));
            root.moved(root._dragValue);
        }

        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: m => {
            root.forceActiveFocus();
            update(m.x);
        }
        onPositionChanged: m => {
            if (pressed)
                update(m.x);
        }
        onWheel: w => {
            root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))));
        }
    }
}
