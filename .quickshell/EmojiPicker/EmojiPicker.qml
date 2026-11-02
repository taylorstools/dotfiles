import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Emoji picker for the emoji key (and Mod+.), laid out like the clipboard
// panel. Opens on recents (or smileys when there are none); typing searches
// every emoji by name.
//   qs ipc call emoji toggle
// Arrows move, Enter types the emoji into the window you were in, Shift+Enter
// copies it instead, Tab / Shift+Tab change category, Esc or a click outside
// closes. The swatches in the corner set the skin tone.
Scope {
    id: root

    property bool shown: false
    property string query: ""
    // -1 = recent, else an index into Emoji.groups.
    property int category: -1

    readonly property var results: {
        if (query.trim() !== "")
            return Emoji.search(query);
        return category < 0 ? Emoji.recent : Emoji.inGroup(category);
    }
    readonly property var current: results[grid.currentIndex] ?? null
    readonly property int columns: 10

    function show() {
        const screens = Array.from(Quickshell.screens);
        const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        if (target)
            window.screen = target;
        query = "";
        category = Emoji.recent.length > 0 ? -1 : 0;
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

    function pick(entry, copyOnly) {
        if (!entry)
            return;
        hide();
        if (copyOnly)
            Emoji.copy(entry);
        else
            Emoji.type(entry);
    }

    // Tab / Shift+Tab: through recent (when there are any) and the groups.
    function stepCategory(step) {
        const first = Emoji.recent.length > 0 ? -1 : 0;
        const count = Emoji.groups.length - first;
        searchInput.text = "";
        category = first + ((category - first + step) % count + count) % count;
    }

    function move(step) {
        const count = grid.count;
        if (count === 0)
            return;
        grid.currentIndex = Math.max(0, Math.min(count - 1, grid.currentIndex + step));
    }

    onCategoryChanged: grid.currentIndex = 0

    IpcHandler {
        target: "emoji"

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

        WlrLayershell.namespace: "qstest:emoji"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                searchInput.text = "";
                grid.currentIndex = 0;
                grid.positionViewAtBeginning();
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
                window.BackgroundEffect.blurRegion = Settings.blur && !Wallpaper.xrayBackdrop ? blurRegion : null;
        }

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        Rectangle {
            id: panel

            // X-ray: the blurred wallpaper under the panel's colour.
            WallpaperBackdrop {
                window: window
                onActiveChanged: window.applyBlur()
            }

            // Fades and grows in from 95%; Settings > Appearance sets the speed.
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

            readonly property real pad: Theme.spacingS

            anchors.centerIn: parent
            width: Config.launcherWidth
            height: Math.min(parent.height - 80, 480)
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
                    // On the panel's own background, underlined.
                    color: "transparent"

                    InputUnderline {}

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
                            grid.currentIndex = 0;
                            grid.positionViewAtBeginning();
                        }

                        // The arrows move through the grid, not the text.
                        Keys.onPressed: event => {
                            const shift = event.modifiers & Qt.ShiftModifier;
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.hide();
                                break;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                root.pick(root.current, shift);
                                break;
                            case Qt.Key_Left:
                                root.move(-1);
                                break;
                            case Qt.Key_Right:
                                root.move(1);
                                break;
                            case Qt.Key_Up:
                                root.move(-root.columns);
                                break;
                            case Qt.Key_Down:
                                root.move(root.columns);
                                break;
                            case Qt.Key_Tab:
                                root.stepCategory(1);
                                break;
                            case Qt.Key_Backtab:
                                root.stepCategory(-1);
                                break;
                            default:
                                return;
                            }
                            event.accepted = true;
                        }

                        StyledText {
                            anchors.fill: parent
                            visible: searchInput.text === ""
                            text: "Search emoji"
                            color: Theme.withAlpha(Theme.surfaceText, 0.45)
                            font.pixelSize: Theme.fontSizeLarge
                        }
                    }
                }

                // Skin tone swatches; the chosen one is ringed.
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    Repeater {
                        model: Emoji.tones

                        Rectangle {
                            id: swatch

                            required property string modelData
                            readonly property bool chosen: Settings.emojiSkinTone === modelData

                            width: 22
                            height: 22
                            radius: 11
                            color: "transparent"
                            border.width: 2
                            border.color: chosen ? Theme.primary : (swatchMouse.containsMouse ? Theme.outline : "transparent")

                            Rectangle {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 7
                                color: Emoji.toneColors[swatch.modelData]
                            }

                            MouseArea {
                                id: swatchMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Settings.emojiSkinTone = swatch.modelData;
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // Categories: recent, then Unicode's groups. Dimmed while
            // searching, since results come from all of them.
            Row {
                id: tabs

                anchors.top: header.bottom
                anchors.topMargin: panel.pad
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                opacity: root.query.trim() === "" ? 1 : 0.5

                Repeater {
                    model: [-1].concat(Emoji.groups.map((g, i) => i))

                    Rectangle {
                        id: tab

                        required property int modelData
                        readonly property bool current: root.query.trim() === "" && root.category === modelData
                        readonly property string label: modelData < 0 ? "Recent" : Emoji.groups[modelData]

                        width: 48
                        height: 34
                        radius: 8
                        color: current ? Theme.primary : (tabMouse.containsMouse ? Theme.widgetHover : "transparent")

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: tab.modelData < 0 ? "schedule" : (Emoji.groupIcons[tab.label] ?? "category")
                            size: 20
                            color: tab.current ? Theme.onPrimary : Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = "";
                                root.category = tab.modelData;
                                searchInput.forceActiveFocus();
                            }
                        }

                        Tooltip {
                            target: tab
                            text: tab.label
                            shown: tabMouse.containsMouse
                        }
                    }
                }
            }

            GridView {
                id: grid

                anchors.top: tabs.bottom
                anchors.topMargin: panel.pad
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.leftMargin: panel.pad
                anchors.rightMargin: panel.pad
                anchors.bottomMargin: panel.pad
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                cellWidth: Math.floor(width / root.columns)
                cellHeight: cellWidth
                model: root.results

                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index
                    readonly property bool selected: GridView.isCurrentItem

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.cornerRadius - panel.pad / 2
                        color: cell.selected ? Theme.withAlpha(Theme.primary, 0.2) : (cellMouse.containsMouse ? Theme.widgetHover : "transparent")
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Emoji.glyph(cell.modelData)
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 28
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Right-click copies, like Shift+Enter.
                        onClicked: mouse => root.pick(cell.modelData, mouse.button === Qt.RightButton)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: !Emoji.loaded ? "Emoji list not found" : (root.query.trim() !== "" ? "No matches" : "Nothing picked yet")
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                }
            }

            // The selected emoji and its name, then the keys.
            RowLayout {
                id: footer

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: panel.pad
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                height: 28
                spacing: Theme.spacingS

                Text {
                    text: Emoji.glyph(root.current)
                    font.family: "Noto Color Emoji"
                    font.pixelSize: 18
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.current?.name ?? ""
                    color: Theme.surfaceVariantText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                StyledText {
                    text: Emoji.typeMethod === "none" ? "⏎ copy · tab category · esc close" : "⏎ type · ⇧⏎ copy · tab category · esc close"
                    color: Theme.outline
                    font.pixelSize: 11
                }
            }
        }
    }
}
