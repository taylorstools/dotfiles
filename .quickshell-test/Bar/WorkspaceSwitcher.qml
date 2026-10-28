import QtQuick
import qs.Common
import qs.Services

// DMS's "pills" workspace indicator: a wide pill for the active workspace,
// narrow ones for the rest, for the workspaces on this bar's monitor.
Item {
    id: root

    property string screenName: ""
    readonly property real thickness: Theme.widgetThickness
    readonly property var workspaces: Niri.workspacesForOutput(screenName)

    implicitWidth: row.implicitWidth
    implicitHeight: thickness

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        Repeater {
            model: root.workspaces.map(ws => ws.id)

            delegate: Item {
                id: pill

                required property var modelData
                readonly property var ws: Niri.workspaces[modelData] ?? null
                readonly property bool isActive: ws ? ws.is_active : false
                readonly property bool isUrgent: ws ? ws.is_urgent : false

                width: isActive ? Math.round(root.thickness * 1.05) : Math.round(root.thickness * 0.7)
                height: root.thickness

                Behavior on width {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: Math.round(root.thickness * 0.5)
                    radius: height / 2
                    color: {
                        if (pill.isActive)
                            return Theme.primary;
                        if (pill.isUrgent)
                            return Theme.error;
                        const base = Theme.withAlpha(Theme.surfaceText, 0.3);
                        return mouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.5) : base;
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Niri.focusWorkspace(pill.modelData)
                }
            }
        }
    }
}
