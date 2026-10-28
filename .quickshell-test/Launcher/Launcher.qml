import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Centered app launcher with a search bar, opened over IPC:
//   qs ipc -p <this folder> call launcher toggle      (or ./run.sh launcher)
// Type to filter, Up/Down (or Tab/Shift+Tab) to move, Enter to launch,
// Esc or a click outside to close. Opens on the monitor niri has focused.
Scope {
    id: root

    property bool shown: false
    property string query: ""
    readonly property var results: Apps.search(query)

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            launcherWindow.screen = target;
        query = "";
        shown = true;
    }

    function hide() {
        shown = false;
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    function launch(entry) {
        if (!entry)
            return;
        hide();
        entry.execute();
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.hide();
        }
    }

    PanelWindow {
        id: launcherWindow

        visible: root.shown
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "qstest:launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                searchInput.text = "";
                resultList.currentIndex = 0;
                searchInput.forceActiveFocus();
                applyBlur();
            }
        }

        Item {
            Region {
                id: blurRegion
                x: panel.x
                y: panel.y
                width: panel.width
                height: panel.height
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (launcherWindow.BackgroundEffect !== undefined)
                launcherWindow.BackgroundEffect.blurRegion = Config.blur ? blurRegion : null;
        }

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: panel

            readonly property real rowHeight: 44
            readonly property real pad: Theme.spacingS

            anchors.centerIn: parent
            width: Config.launcherWidth
            height: pad * 3 + searchBox.height + rowHeight * Config.launcherVisibleRows
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallow clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: searchBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                height: 44
                radius: Theme.cornerRadius - panel.pad / 2
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.9)

                MaterialIcon {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 20
                    color: Theme.surfaceVariantText
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceText
                    selectionColor: Theme.primarySelected
                    selectedTextColor: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLarge
                    clip: true
                    focus: true

                    onTextChanged: {
                        root.query = text;
                        resultList.currentIndex = 0;
                    }

                    Keys.onPressed: event => {
                        const count = resultList.count;
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.hide();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.launch(root.results[resultList.currentIndex]);
                            break;
                        case Qt.Key_Down:
                        case Qt.Key_Tab:
                            if (count > 0)
                                resultList.currentIndex = (resultList.currentIndex + 1) % count;
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_Backtab:
                            if (count > 0)
                                resultList.currentIndex = (resultList.currentIndex - 1 + count) % count;
                            break;
                        case Qt.Key_PageDown:
                            resultList.currentIndex = Math.min(count - 1, resultList.currentIndex + Config.launcherVisibleRows);
                            break;
                        case Qt.Key_PageUp:
                            resultList.currentIndex = Math.max(0, resultList.currentIndex - Config.launcherVisibleRows);
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }

                    StyledText {
                        anchors.fill: parent
                        visible: searchInput.text === ""
                        text: "Search apps"
                        color: Theme.withAlpha(Theme.surfaceText, 0.45)
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }
            }

            ListView {
                id: resultList
                anchors.top: searchBox.bottom
                anchors.topMargin: panel.pad
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                anchors.bottomMargin: panel.pad
                clip: true
                model: root.results
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem

                    width: ListView.view.width
                    height: panel.rowHeight
                    radius: Theme.cornerRadius - panel.pad / 2
                    color: selected ? Theme.withAlpha(Theme.primary, 0.2) : (rowMouse.containsMouse ? Theme.widgetHover : "transparent")

                    IconImage {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 28
                        source: Apps.resolveIcon(row.modelData.icon)
                        asynchronous: true
                    }

                    MaterialIcon {
                        anchors.centerIn: appIcon
                        visible: appIcon.status !== Image.Ready
                        name: "apps"
                        size: 24
                        color: Theme.surfaceVariantText
                    }

                    Column {
                        anchors.left: appIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        StyledText {
                            width: parent.width
                            text: row.modelData.name || ""
                            font.pixelSize: Theme.fontSizeMedium
                            color: row.selected ? Theme.primary : Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            visible: text !== ""
                            text: row.modelData.genericName || row.modelData.comment || ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.6)
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launch(row.modelData)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: resultList.count === 0
                    text: "No matching apps"
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }
        }
    }
}
