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
// Esc or a click outside to close. Right-click an app to pin it to the dock.
// Opens on the monitor niri has focused.
Scope {
    id: root

    property bool shown: false
    property string query: ""
    // The app whose right-click menu is open, and where it was clicked.
    property var menuEntry: null
    property point menuPos
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
        menuEntry = null;
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


    // Keeps the window up until the closing animation is done.
    PanelMotion {
        id: motion
        shown: root.shown
    }

    PanelWindow {
        id: launcherWindow

        visible: motion.mapped
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
            // Follows the panel's open/close scaling, so the blur grows with it.
            Region {
                id: blurRegion
                x: panel.x + panel.width * (1 - panel.scale) / 2
                y: panel.y + panel.height * (1 - panel.scale) / 2
                width: panel.width * panel.scale
                height: panel.height * panel.scale
            }
        }

        // Re-apply when blur is switched in the settings window.
        Connections {
            target: Settings
            function onBlurChanged() {
                launcherWindow.applyBlur();
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (launcherWindow.BackgroundEffect !== undefined)
                launcherWindow.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
        }

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: panel

            // Fades and grows in from 95%; Settings > Appearance sets the speed.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

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
                onClicked: root.menuEntry = null
            }

            Rectangle {
                id: searchBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                height: 44
                radius: Theme.cornerRadius - panel.pad / 2
                color: Theme.overlay(Theme.surfaceContainerHigh, 0.9)

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
                    font.weight: Theme.fontWeight
                    font.pixelSize: Theme.fontSizeLarge
                    clip: true
                    focus: true

                    onTextChanged: {
                        root.menuEntry = null;
                        root.query = text;
                        resultList.currentIndex = 0;
                    }

                    Keys.onPressed: event => {
                        const count = resultList.count;
                        switch (event.key) {
                        case Qt.Key_Escape:
                            if (root.menuEntry)
                                root.menuEntry = null;
                            else
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.menuPos = mapToItem(panel, mouse.x, mouse.y);
                                root.menuEntry = row.modelData;
                            } else {
                                root.launch(row.modelData);
                            }
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: resultList.count === 0
                    text: "No matching apps"
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }

            // Right-click menu for an app row.
            Rectangle {
                id: appMenu

                readonly property string appId: root.menuEntry?.id ?? ""
                readonly property bool pinned: DockApps.isPinned(appId)

                x: Math.min(root.menuPos.x, panel.width - width - panel.pad)
                y: Math.min(root.menuPos.y, panel.height - height - panel.pad)
                z: 10
                width: pinRow.implicitWidth + Theme.spacingM * 2
                height: 36
                visible: root.menuEntry !== null
                radius: Theme.cornerRadius - panel.pad / 2
                color: pinMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)

                Row {
                    id: pinRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: appMenu.pinned ? "keep_off" : "keep"
                        size: 16
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: appMenu.pinned ? "Unpin from dock" : "Pin to dock"
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                MouseArea {
                    id: pinMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        DockApps.togglePin(appMenu.appId);
                        root.menuEntry = null;
                    }
                }
            }
        }
    }
}
