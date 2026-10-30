import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Clipboard history, laid out like the launcher. Pinned entries first, then
// the rest, newest first.
//   qs ipc -p <this folder> call clipboard toggle     (or ./run.sh clipboard)
// Type to filter, Up/Down to move, Enter or a click pastes into the window
// you were in, Ctrl+P pins, Delete removes, Esc or a click outside closes.
Scope {
    id: root

    property bool shown: false
    property string query: ""
    // The app that had focus when this opened; it gets the paste.
    property string targetAppId: ""

    readonly property var results: {
        const q = query.toLowerCase();
        const match = ClipboardHistory.entries.filter(e => q === "" || (e.kind === "image" ? "image" : e.preview.toLowerCase()).includes(q));
        return match.filter(e => e.pinned).concat(match.filter(e => !e.pinned));
    }
    readonly property var current: results[list.currentIndex] ?? null

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            window.screen = target;
        targetAppId = Niri.windows[Niri.focusedWindowId]?.app_id ?? "";
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

    function paste(entry) {
        if (!entry)
            return;
        hide();
        ClipboardHistory.paste(entry, targetAppId);
    }

    // "now", "5 min", "2 hr", "yesterday", then the date.
    function ago(time) {
        const minutes = Math.floor((Date.now() - time) / 60000);
        if (minutes < 1)
            return "now";
        if (minutes < 60)
            return minutes + " min";
        if (minutes < 24 * 60)
            return Math.floor(minutes / 60) + " hr";
        if (minutes < 48 * 60)
            return "yesterday";
        return Qt.formatDate(new Date(time), "M/d");
    }

    function kindIcon(entry) {
        if (/^https?:\/\//.test(entry.preview))
            return "link";
        if (/^#[0-9a-fA-F]{6}$/.test(entry.preview))
            return "palette";
        return "notes";
    }

    IpcHandler {
        target: "clipboard"

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
        id: window

        visible: motion.mapped
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.namespace: "qstest:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                searchInput.text = "";
                list.currentIndex = 0;
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
                window.applyBlur();
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
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

            readonly property real rowHeight: 46
            readonly property real pad: Theme.spacingS

            anchors.centerIn: parent
            width: Config.launcherWidth
            height: Math.min(parent.height - 80, 560)
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            // Swallow clicks so they don't reach the close-on-click area.
            MouseArea {
                anchors.fill: parent
            }

            RowLayout {
                id: header

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                height: 44
                spacing: panel.pad

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                            root.query = text;
                            list.currentIndex = 0;
                        }

                        Keys.onPressed: event => {
                            const count = list.count;
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (ctrl && event.key === Qt.Key_P) {
                                if (root.current)
                                    ClipboardHistory.togglePin(root.current.id);
                                event.accepted = true;
                                return;
                            }
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.hide();
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                root.paste(root.current);
                                break;
                            case Qt.Key_Down:
                            case Qt.Key_Tab:
                                if (count > 0)
                                    list.currentIndex = (list.currentIndex + 1) % count;
                                break;
                            case Qt.Key_Up:
                            case Qt.Key_Backtab:
                                if (count > 0)
                                    list.currentIndex = (list.currentIndex - 1 + count) % count;
                                break;
                            case Qt.Key_Delete:
                                if (root.current)
                                    ClipboardHistory.remove(root.current.id);
                                break;
                            default:
                                return;
                            }
                            event.accepted = true;
                        }

                        StyledText {
                            anchors.fill: parent
                            visible: searchInput.text === ""
                            text: "Search clipboard"
                            color: Theme.withAlpha(Theme.surfaceText, 0.45)
                            font.pixelSize: Theme.fontSizeLarge
                        }
                    }
                }

                // Clear all (pinned too, unless that's switched off in settings).
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: clearRow.implicitWidth + Theme.spacingM * 2
                    radius: Theme.cornerRadius - panel.pad / 2
                    color: clearMouse.containsMouse ? Theme.widgetHover : Theme.overlay(Theme.surfaceContainerHigh, 0.9)

                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "delete_sweep"
                            size: 18
                            color: Theme.error
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear all"
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ClipboardHistory.clear();
                            searchInput.forceActiveFocus();
                        }
                    }
                }
            }

            ListView {
                id: list

                anchors.top: header.bottom
                anchors.topMargin: panel.pad
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: hints.top
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                anchors.bottomMargin: panel.pad
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                model: root.results

                // The first row of each group carries its "Pinned" / "Recent"
                // label, so Up/Down only ever lands on entries.
                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property bool isImage: modelData.kind === "image"
                    readonly property bool isColor: /^#[0-9a-fA-F]{6}$/.test(modelData.preview)
                    readonly property bool firstOfGroup: index === 0 || root.results[index - 1]?.pinned !== modelData.pinned
                    readonly property real labelHeight: firstOfGroup ? 26 : 0

                    width: ListView.view.width
                    height: panel.rowHeight + labelHeight

                    StyledText {
                        visible: row.firstOfGroup
                        height: row.labelHeight
                        leftPadding: Theme.spacingM
                        bottomPadding: 4
                        verticalAlignment: Text.AlignBottom
                        text: row.modelData.pinned ? "Pinned" : "Recent"
                        color: Theme.outline
                        font.pixelSize: 11
                    }

                    Rectangle {
                        anchors.fill: rowMouse
                        radius: Theme.cornerRadius - panel.pad / 2
                        color: row.selected ? Theme.withAlpha(Theme.primary, 0.2) : (rowMouse.containsMouse ? Theme.widgetHover : "transparent")
                    }

                    MouseArea {
                        id: rowMouse
                        y: row.labelHeight
                        width: parent.width
                        height: panel.rowHeight
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            list.currentIndex = row.index;
                            root.paste(row.modelData);
                        }
                    }

                    RowLayout {
                        anchors.fill: rowMouse
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS

                        // A thumbnail for images, a type icon for text.
                        Item {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 28

                            ClippingRectangle {
                                anchors.fill: parent
                                visible: row.isImage
                                radius: 5
                                color: Theme.surfaceContainerHighest

                                Image {
                                    anchors.fill: parent
                                    source: row.isImage ? "file://" + ClipboardHistory.fileFor(row.modelData) : ""
                                    sourceSize.width: 88
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: !row.isImage
                                name: root.kindIcon(row.modelData)
                                size: 20
                                color: Theme.outline
                            }
                        }

                        Rectangle {
                            visible: row.isColor
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            radius: 3
                            color: row.isColor ? row.modelData.preview : "transparent"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.isImage ? "Image · " + Math.max(1, Math.round(row.modelData.bytes / 1024)) + " KB" : row.modelData.preview
                            textFormat: Text.PlainText
                            color: row.selected ? Theme.surfaceText : Theme.surfaceVariantText
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: !row.modelData.pinned
                            text: root.ago(row.modelData.time)
                            color: Theme.outline
                            font.pixelSize: 11
                        }

                        IconButton {
                            implicitHeight: 28
                            icon: "keep"
                            iconSize: 18
                            filled: row.modelData.pinned
                            contentColor: row.modelData.pinned ? Theme.primary : Theme.outline
                            onClicked: ClipboardHistory.togglePin(row.modelData.id)
                        }

                        IconButton {
                            implicitHeight: 28
                            icon: "close"
                            iconSize: 18
                            contentColor: Theme.outline
                            onClicked: ClipboardHistory.remove(row.modelData.id)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: ClipboardHistory.entries.length === 0 ? "Clipboard history is empty" : "No matches"
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }

            StyledText {
                id: hints
                anchors.bottom: parent.bottom
                anchors.bottomMargin: panel.pad
                anchors.horizontalCenter: parent.horizontalCenter
                text: ClipboardHistory.pasteMethod === "none" ? "↑↓ move · ⏎ copy · ^P pin · Del delete · esc close" : "↑↓ move · ⏎ paste · ^P pin · Del delete · esc close"
                color: Theme.outline
                font.pixelSize: 11
            }
        }
    }
}
