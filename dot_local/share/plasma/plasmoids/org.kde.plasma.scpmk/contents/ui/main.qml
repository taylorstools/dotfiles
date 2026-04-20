import QtQuick 
import QtQml
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.quicklaunch // Logic
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    property var iconSett: Plasmoid.configuration.icon
    property bool showCmd1: plasmoid.configuration.showCmd1
    property bool showCmd2: plasmoid.configuration.showCmd2
    property bool showCmd3: plasmoid.configuration.showCmd3

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 12

    Plasma5Support.DataSource {
        id: apps
        engine: "apps"

        property string appListConfig: Plasmoid.configuration.appList
        property ListModel model: ListModel {}
        property var userApps
        
        onNewData: {
            model.append(Object.assign({}, data, userApps.get(sourceName)))
            disconnectSource(sourceName)
        }

        onAppListConfigChanged: {
            model.clear()
            userApps = new Map(JSON.parse(appListConfig))
            Array.from(userApps.keys()).forEach(connectSource)
        }
    }
    
    Logic {
        id: kRun
        
        function launch(desktopFile) {
            openUrl('file:' + desktopFile)
        }
    }

    compactRepresentation: Item {
        id: compactRoot

        Row {
            anchors.centerIn: parent

            Kirigami.Icon {
                id: icon
                width: height
                height: compactRoot.height
                source: visible ? (iconSett || "configure") : ""

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.expanded = !root.expanded
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    fullRepresentation: Item {
        id: fullRoot

        implicitHeight: column.implicitHeight
        implicitWidth: column.implicitWidth

        Layout.preferredWidth: Kirigami.Units.gridUnit * 15
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Screen.height/* / 2*/

        Sessions.SessionManagement {
            id: sm
        }

        ColumnLayout {
            id: column

            anchors.fill: parent
            spacing: 0

            ColumnLayout {
                id: appColumn
                Repeater {
                    model: apps.model
                    
                    ActionListDelegate {
                        text: model.name
                        icon.name: model.iconName
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: kRun.launch(model.entryPath)
                        }
                    }
                }
            }

            ToolSeparator {
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.topMargin: 5
                orientation: Qt.Horizontal
                visible: root.showCmd1 || root.showCmd2 || root.showCmd3
            }

            RowLayout {
                id: buttonRow
                visible: root.showCmd1
                Layout.preferredWidth: parent.width
                Layout.topMargin: 5

                Button {
                    id: lock
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width / 2.05
                    text: i18n("Lock Screen")
                    highlighted : true
                    icon.width: 1.4 * Kirigami.Units.iconSizes.small
                    icon.height: 1.4 * Kirigami.Units.iconSizes.small
                    icon.source: "system-lock-screen"
                    MouseArea {
                        id: mouseArea1
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.lock()
                    }
                }

                Button {
                    id: logout
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width / 2.05
                    text: i18n("Log Out")
                    highlighted : true
                    icon.width: 1.4 * Kirigami.Units.iconSizes.small
                    icon.height: 1.4 * Kirigami.Units.iconSizes.small
                    icon.source: "system-log-out"
                    MouseArea {
                        id: mouseArea2
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.requestLogout()
                    }
                }
            }

            RowLayout {
                id: buttonRow2
                visible: root.showCmd2
                Layout.preferredWidth: parent.width
                Layout.topMargin: 5

                Button {
                    id: restart
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width / 2.05
                    text: i18n("Restart")
                    highlighted : true
                    icon.width: 1.4 * Kirigami.Units.iconSizes.small
                    icon.height: 1.4 * Kirigami.Units.iconSizes.small
                    icon.source: "system-reboot"
                    MouseArea {
                        id: mouseArea3
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.requestReboot()
                    }
                }

                Button {
                    id: suspend
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width / 2.05
                    text: i18n("Sleep")
                    highlighted : true
                    icon.width: 1.4 * Kirigami.Units.iconSizes.small
                    icon.height: 1.4 * Kirigami.Units.iconSizes.small
                    icon.source: "system-suspend"
                    MouseArea {
                        id: mouseArea4
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.suspend()
                    }
                }
            }

            RowLayout {
                id: buttonRow3
                visible: root.showCmd3
                Layout.topMargin: 5

                Button {
                    id: power
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    text: i18n("Shut Down")
                    highlighted : true
                    icon.width: 1.4 * Kirigami.Units.iconSizes.small
                    icon.height: 1.4 * Kirigami.Units.iconSizes.small
                    icon.source: "system-shutdown"
                    MouseArea {
                        id: mouseArea5
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sm.requestShutdown()
                    }
                }
            }
        }
    }
}
