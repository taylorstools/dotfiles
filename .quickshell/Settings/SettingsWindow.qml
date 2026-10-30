import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Wallpaper
import qs.Widgets

// Shell Settings, in a normal window niri tiles like any app. Opened from
// the control center's gear, the launcher (org.quickshell.desktop), or
//   qs ipc call settings toggle
// New pages go in `pages` below, plus a layout shown when `page` matches;
// new settings also go in `searchIndex` so the sidebar search finds them.
Scope {
    id: root

    property string page: "power"
    readonly property var pages: [
        {
            "id": "appearance",
            "title": "Appearance",
            "icon": "palette"
        },
        {
            "id": "power",
            "title": "Power",
            "icon": "power_settings_new"
        },
        {
            "id": "wallpaper",
            "title": "Wallpaper",
            "icon": "wallpaper"
        },
        {
            "id": "taskbar",
            "title": "Taskbar",
            "icon": "call_to_action"
        },
        {
            "id": "dock",
            "title": "Dock",
            "icon": "dock_to_left"
        },
        {
            "id": "clipboard",
            "title": "Clipboard",
            "icon": "content_paste"
        }
    ]

    // What the sidebar search looks through: one entry per setting, with the
    // page it's on and extra words people might type for it. Every word of
    // the query has to appear in the label, the page title or the terms.
    readonly property var searchIndex: [
        { "page": "appearance", "label": "Font", "terms": "typeface text family inter" },
        { "page": "appearance", "label": "Font weight", "terms": "typeface text bold medium regular" },
        { "page": "appearance", "label": "Monospace font", "terms": "typeface fixed width code command" },
        { "page": "appearance", "label": "Background opacity", "terms": "transparency transparent see-through panels" },
        { "page": "appearance", "label": "Overlay opacity", "terms": "cards rows fields buttons grey gray inner fill transparency" },
        { "page": "appearance", "label": "Animation duration", "terms": "speed motion slide fade open close" },
        { "page": "appearance", "label": "Attach flyouts to the taskbar", "terms": "connected floating windows 10 control center calendar clock notepad gap corners edge" },
        { "page": "appearance", "label": "Flyout corner radius", "terms": "rounded corners border radius control center calendar clock" },
        { "page": "appearance", "label": "Night light", "terms": "night mode blue light filter warm wlsunset" },
        { "page": "appearance", "label": "Night light warmth", "terms": "night mode temperature kelvin warm colour color" },
        { "page": "appearance", "label": "Blur behind panels", "terms": "frosted glass background effect" },
        { "page": "appearance", "label": "Blur strength", "terms": "frosted glass amount niri" },
        { "page": "appearance", "label": "X-ray blur", "terms": "xray wallpaper only windows behind see through frosted glass" },
        { "page": "appearance", "label": "Surface tint colour", "terms": "color tint accent primary secondary tertiary custom matugen grey gray background panels" },
        { "page": "appearance", "label": "Custom tint colour", "terms": "color hex picker eyedropper tint" },
        { "page": "appearance", "label": "Tint intensity", "terms": "tint amount strength colour color accent surfaces" },
        { "page": "appearance", "label": "Border colour", "terms": "panel border outline color accent primary custom flyout launcher notepad" },
        { "page": "appearance", "label": "Border opacity", "terms": "panel border outline transparency hide" },
        { "page": "appearance", "label": "Border on attached flyouts and notepad", "terms": "panel border outline attached control center calendar notepad" },
        { "page": "power", "label": "Lock command", "terms": "lock screen hyprlock swaylock" },
        { "page": "power", "label": "Sleep command", "terms": "suspend hibernate" },
        { "page": "power", "label": "Restart command", "terms": "reboot" },
        { "page": "power", "label": "Shut down command", "terms": "shutdown power off poweroff" },
        { "page": "wallpaper", "label": "Wallpaper folder", "terms": "directory path pictures background" },
        { "page": "wallpaper", "label": "Colour scheme", "terms": "color matugen scheme type vibrant tonal neutral palette theme" },
        { "page": "wallpaper", "label": "Fade between wallpapers", "terms": "crossfade transition animation background" },
        { "page": "wallpaper", "label": "Colourful base colour", "terms": "color saturated seed vivid palette theme" },
        { "page": "wallpaper", "label": "Random wallpaper", "terms": "shuffle background" },
        { "page": "wallpaper", "label": "Choose a wallpaper", "terms": "pick picker background image" },
        { "page": "taskbar", "label": "Larger app icons", "terms": "running apps icon size big" },
        { "page": "taskbar", "label": "Current workspace only", "terms": "running apps windows filter" },
        { "page": "taskbar", "label": "Group windows by app", "terms": "running apps combine count badge" },
        { "page": "taskbar", "label": "Max bar coverage", "terms": "running apps width percent shrink labels" },
        { "page": "taskbar", "label": "Hard width cap", "terms": "running apps max width pixels limit" },
        { "page": "taskbar", "label": "Full label width", "terms": "running apps title width" },
        { "page": "taskbar", "label": "Minimum label width", "terms": "running apps icon only title" },
        { "page": "taskbar", "label": "Reserved right-side space", "terms": "running apps width budget" },
        { "page": "dock", "label": "Show the dock", "terms": "enable disable taskbar apps" },
        { "page": "dock", "label": "Dock position", "terms": "left right side edge" },
        { "page": "dock", "label": "Auto-hide the dock", "terms": "hide autohide screen edge pointer" },
        { "page": "dock", "label": "Dock border", "terms": "outline" },
        { "page": "dock", "label": "Dock icon size", "terms": "bigger smaller scale" },
        { "page": "dock", "label": "Dock spacing", "terms": "gap padding" },
        { "page": "dock", "label": "Pinned apps", "terms": "pin unpin favourites favorites order" },
        { "page": "clipboard", "label": "Clear all also removes pinned items", "terms": "clipboard history pins delete" },
        { "page": "clipboard", "label": "Clear history at login", "terms": "clipboard startup boot delete" },
        { "page": "clipboard", "label": "Paste into apps", "terms": "wtype ctrl+v clipboard" }
    ]

    property string query: ""
    readonly property var results: {
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "");
        if (words.length === 0)
            return [];
        const pageInfo = {};
        for (const p of pages)
            pageInfo[p.id] = p;
        // The pages themselves come first, then their settings.
        const items = pages.map(p => ({
                    "page": p.id,
                    "label": p.title,
                    "terms": "",
                    "isPage": true
                })).concat(searchIndex);
        return items.filter(item => {
            const haystack = (item.label + " " + pageInfo[item.page].title + " " + item.terms).toLowerCase();
            return words.every(w => haystack.includes(w));
        }).map(item => Object.assign({}, item, {
                    "pageTitle": pageInfo[item.page].title,
                    "icon": pageInfo[item.page].icon
                }));
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            Popouts.settingsOpen = !Popouts.settingsOpen;
        }
        function open(): void {
            Popouts.settingsOpen = true;
        }
        function close(): void {
            Popouts.settingsOpen = false;
        }
    }

    LazyLoader {
        active: Popouts.settingsOpen

        FloatingWindow {
            id: window

            title: "Shell Settings"
            implicitWidth: 760
            implicitHeight: 560
            color: Theme.popupBackground
            visible: true

            // Closing the window from niri hides it; drop the loader too.
            onVisibleChanged: {
                if (!visible)
                    Popouts.settingsOpen = false;
                else
                    applyBlur();
            }

            // Blur behind the whole window, like the shell's panels.
            Item {
                Region {
                    id: blurRegion
                    width: window.width
                    height: window.height
                }
            }

            function applyBlur() {
                if (window.BackgroundEffect !== undefined)
                    window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
            }

            Component.onCompleted: applyBlur()

            Connections {
                target: Settings
                function onBlurChanged() {
                    window.applyBlur();
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Title bar: niri draws no decorations, so the window has its
                // own maximize and close. Maximize is niri's
                // maximize-window-to-edges, on this (focused) window.
                Rectangle {
                    id: titleBar

                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: Theme.withAlpha(Theme.surface, 0.5)

                    function toggleMaximized() {
                        Quickshell.execDetached(["niri", "msg", "action", "maximize-window-to-edges"]);
                    }

                    // Double-click the bar to maximize, like most title bars.
                    // Declared before the buttons, so they keep their clicks.
                    MouseArea {
                        anchors.fill: parent
                        onDoubleClicked: titleBar.toggleMaximized()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS

                        MaterialIcon {
                            name: "settings"
                            size: 18
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Shell Settings"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall + 1
                        }

                        IconButton {
                            implicitHeight: 32
                            icon: "crop_square"
                            iconSize: 18
                            contentColor: Theme.surfaceVariantText
                            onClicked: titleBar.toggleMaximized()

                            Tooltip {
                                target: parent
                                shown: parent.hovered
                                text: "Maximize"
                            }
                        }

                        IconButton {
                            id: closeButton
                            implicitHeight: 32
                            icon: "close"
                            iconSize: 18
                            contentColor: closeButton.hovered ? Theme.error : Theme.surfaceVariantText
                            onClicked: Popouts.settingsOpen = false

                            Tooltip {
                                target: parent
                                shown: parent.hovered
                                text: "Close"
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 200
                        // A darker strip over the (translucent) window background.
                        color: Theme.withAlpha(Theme.surface, 0.5)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS

                            // Search: typing swaps the page list for matching
                            // settings; Enter opens the first, Escape clears.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                radius: Theme.cornerRadius / 1.5
                                color: Theme.surface
                                border.width: 1
                                border.color: search.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingXXS
                                    spacing: Theme.spacingS

                                    MaterialIcon {
                                        name: "search"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                    }

                                    TextInput {
                                        id: search

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.surfaceText
                                        selectionColor: Theme.primarySelected
                                        selectedTextColor: Theme.surfaceText
                                        font.family: Theme.fontFamily
                                        font.weight: Theme.fontWeight
                                        font.pixelSize: 13
                                        selectByMouse: true
                                        clip: true
                                        focus: true
                                        onTextChanged: root.query = text
                                        onAccepted: {
                                            if (root.results.length > 0)
                                                root.page = root.results[0].page;
                                        }
                                        Keys.onEscapePressed: text = ""

                                        Component.onCompleted: {
                                            text = root.query;
                                            forceActiveFocus();
                                        }

                                        StyledText {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            visible: search.text === ""
                                            text: "Search settings"
                                            color: Theme.withAlpha(Theme.surfaceText, 0.4)
                                            font.pixelSize: 13
                                        }
                                    }

                                    IconButton {
                                        visible: search.text !== ""
                                        implicitHeight: 28
                                        icon: "close"
                                        iconSize: 16
                                        contentColor: Theme.surfaceVariantText
                                        onClicked: search.text = ""
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingS
                                visible: root.query.trim() !== "" && root.results.length === 0
                                text: "No settings match"
                                color: Theme.outline
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.query.trim() !== ""
                                contentHeight: resultColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: resultColumn

                                    width: parent.width
                                    spacing: Theme.spacingXXS

                                    Repeater {
                                        model: root.results

                                        delegate: Rectangle {
                                            id: resultItem

                                            required property var modelData
                                            required property int index
                                            readonly property bool current: root.page === modelData.page

                                            width: parent.width
                                            height: resultText.implicitHeight + Theme.spacingS * 2
                                            radius: Theme.cornerRadius / 1.5
                                            color: resultMouse.containsMouse ? Theme.widgetHover : (index === 0 ? Theme.withAlpha(Theme.primary, 0.1) : "transparent")

                                            Row {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.rightMargin: Theme.spacingS
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: Theme.spacingM

                                                MaterialIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: resultItem.modelData.icon
                                                    size: 18
                                                    color: resultItem.current ? Theme.primary : Theme.surfaceVariantText
                                                }

                                                Column {
                                                    id: resultText

                                                    width: parent.width - 18 - Theme.spacingM
                                                    spacing: 1

                                                    StyledText {
                                                        width: parent.width
                                                        text: resultItem.modelData.label
                                                        color: resultItem.current ? Theme.primary : Theme.surfaceText
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                    }

                                                    StyledText {
                                                        width: parent.width
                                                        text: resultItem.modelData.isPage ? "Page" : resultItem.modelData.pageTitle
                                                        color: Theme.outline
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: resultMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.page = resultItem.modelData.page
                                            }
                                        }
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.query.trim() === ""
                                spacing: Theme.spacingXXS

                                Repeater {
                                    model: root.pages

                                    delegate: Rectangle {
                                        id: navItem

                                        required property var modelData
                                        readonly property bool current: root.page === modelData.id

                                        width: parent.width
                                        height: 38
                                        radius: Theme.cornerRadius / 1.5
                                        color: current ? Theme.withAlpha(Theme.primary, 0.18) : (navMouse.containsMouse ? Theme.widgetHover : "transparent")

                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.spacingM

                                            MaterialIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: navItem.modelData.icon
                                                size: 18
                                                color: navItem.current ? Theme.primary : Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: navItem.modelData.title
                                                color: navItem.current ? Theme.primary : Theme.surfaceVariantText
                                            }
                                        }

                                        MouseArea {
                                            id: navMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.page = navItem.modelData.id
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Theme.spacingXL
                        spacing: Theme.spacingL
                        visible: root.page === "power"

                        StyledText {
                            text: "Power"
                            font.pixelSize: Theme.fontSizeXLarge
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "What the control center's lock button and power menu run. Each command runs with sh -c, so $HOME, pipes and ; work."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            CommandLabel {
                                icon: "lock"
                                text: "Lock"
                            }
                            CommandField {
                                key: "lockCommand"
                            }
                            ResetButton {
                                key: "lockCommand"
                            }

                            CommandLabel {
                                icon: "bedtime"
                                text: "Sleep"
                            }
                            CommandField {
                                key: "sleepCommand"
                            }
                            ResetButton {
                                key: "sleepCommand"
                            }

                            CommandLabel {
                                icon: "restart_alt"
                                text: "Restart"
                            }
                            CommandField {
                                key: "restartCommand"
                            }
                            ResetButton {
                                key: "restartCommand"
                            }

                            CommandLabel {
                                icon: "power_settings_new"
                                text: "Shut down"
                            }
                            CommandField {
                                key: "shutdownCommand"
                            }
                            ResetButton {
                                key: "shutdownCommand"
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Saved to " + Settings.path
                            color: Theme.outline
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideMiddle
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Theme.spacingXL
                        spacing: Theme.spacingL
                        visible: root.page === "wallpaper"

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: "Wallpaper"
                                font.pixelSize: Theme.fontSizeXLarge
                            }

                            IconButton {
                                icon: "shuffle"
                                text: "Random"
                                restColor: Theme.surfaceContainerHigh
                                onClicked: Wallpaper.random()
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Wallpaper.lastError !== "" ? Wallpaper.lastError : "Colours for the whole shell are made from the wallpaper with matugen. Changes apply live."
                            color: Wallpaper.lastError !== "" ? Theme.error : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            CommandLabel {
                                icon: "folder"
                                text: "Folder"
                            }
                            CommandField {
                                key: "wallpaperFolder"
                            }
                            ResetButton {
                                key: "wallpaperFolder"
                            }
                        }

                        // matugen --type
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingS

                            Repeater {
                                model: Wallpaper.schemes

                                delegate: Rectangle {
                                    id: chip

                                    required property string modelData
                                    readonly property bool current: Settings.matugenScheme === modelData

                                    width: chipText.implicitWidth + Theme.spacingM * 2
                                    height: 30
                                    radius: height / 2
                                    color: current ? Theme.primary : (chipMouse.containsMouse ? Theme.widgetHover : Theme.surfaceContainerHigh)

                                    StyledText {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: chip.modelData.replace("scheme-", "")
                                        color: chip.current ? Theme.onPrimary : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Settings.matugenScheme = chip.modelData
                                    }
                                }
                            }
                        }

                        SettingRow {
                            label: "Fade between wallpapers"
                            StyledSlider {
                                Layout.preferredWidth: 200
                                value: Settings.wallpaperFadeDuration / 2000
                                steps: 20
                                onMoved: v => Settings.wallpaperFadeDuration = Math.round(v * 20) * 100
                            }
                            ValueText {
                                text: Settings.wallpaperFadeDuration === 0 ? "Off" : (Settings.wallpaperFadeDuration / 1000).toFixed(1) + " s"
                            }
                        }

                        SettingRow {
                            label: "Colourful base colour (build from the wallpaper's most saturated colour)"
                            Toggle {
                                checked: Settings.colorfulSeed
                                onToggled: Settings.colorfulSeed = !Settings.colorfulSeed
                            }
                        }

                        WallpaperPicker {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }

                    // Scrolls: this page has more rows than the window's height.
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.page === "appearance"
                        contentHeight: appearanceColumn.implicitHeight + Theme.spacingXL * 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: appearanceColumn

                            x: Theme.spacingXL
                            y: Theme.spacingXL
                            width: parent.width - Theme.spacingXL * 2
                            spacing: Theme.spacingM

                            StyledText {
                                text: "Appearance"
                                font.pixelSize: Theme.fontSizeXLarge
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "These apply to every panel: the taskbar, dock, launcher, runner, clipboard, flyouts, notepad, OSD, notifications, menus and this window. Animation duration sets how long panels take to open, close and slide; 0 turns animations off."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            FontSetting {
                                label: "Font"
                                key: "fontFamily"
                                description: "Everything in the shell, from the taskbar to the settings window."
                            }

                            SettingRow {
                                label: "Font weight"
                                Repeater {
                                    model: [
                                        {
                                            "id": "regular",
                                            "title": "Regular"
                                        },
                                        {
                                            "id": "medium",
                                            "title": "Medium"
                                        }
                                    ]

                                    delegate: Rectangle {
                                        id: weightChip

                                        required property var modelData
                                        readonly property bool current: (Settings.fontWeight || "medium") === modelData.id

                                        implicitWidth: weightText.implicitWidth + Theme.spacingM * 2
                                        implicitHeight: 28
                                        radius: height / 2
                                        color: current ? Theme.primary : (weightMouse.containsMouse ? Theme.widgetHover : Theme.surfaceContainerHigh)

                                        StyledText {
                                            id: weightText
                                            anchors.centerIn: parent
                                            text: weightChip.modelData.title
                                            color: weightChip.current ? Theme.onPrimary : Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: weightChip.modelData.id === "regular" ? Font.Normal : Font.Medium
                                        }

                                        MouseArea {
                                            id: weightMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Settings.fontWeight = weightChip.modelData.id
                                        }
                                    }
                                }
                            }

                            FontSetting {
                                label: "Monospace font"
                                key: "monoFontFamily"
                                description: "Command and colour fields in this window."
                            }

                            SettingRow {
                                label: "Background opacity"
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: (Settings.surfaceOpacity - 0.3) / 0.7
                                    steps: 70
                                    onMoved: v => Settings.surfaceOpacity = Math.round((0.3 + v * 0.7) * 100) / 100
                                }
                                ValueText {
                                    text: Math.round(Settings.surfaceOpacity * 100) + "%"
                                }
                            }

                            SettingRow {
                                label: "Overlay opacity (cards, rows, fields and buttons inside panels)"
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.overlayOpacity
                                    steps: 100
                                    onMoved: v => Settings.overlayOpacity = Math.round(v * 100) / 100
                                }
                                ValueText {
                                    text: Math.round(Settings.overlayOpacity * 100) + "%"
                                }
                            }

                            SettingRow {
                                label: "Animation duration"
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.animationDuration / 400
                                    steps: 40
                                    onMoved: v => Settings.animationDuration = Math.round(v * 40) * 10
                                }
                                ValueText {
                                    text: Settings.animationDuration === 0 ? "Off" : Settings.animationDuration + " ms"
                                }
                            }

                            SettingRow {
                                label: "Attach flyouts to the taskbar"
                                description: "The control center, calendar and notepad sit against the taskbar and screen edge, like Windows 10. Off, they float with a gap."
                                Toggle {
                                    checked: Settings.attachPanels
                                    onToggled: Settings.attachPanels = !Settings.attachPanels
                                }
                            }

                            SettingRow {
                                label: "Flyout corner radius"
                                description: "The control center and calendar, attached or floating. Attached, only the corner away from the taskbar and screen edge is rounded; the notepad stays square."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Theme.flyoutRadius / 30
                                    steps: 30
                                    onMoved: v => Settings.flyoutRadius = Math.round(v * 30)
                                }
                                ValueText {
                                    text: Theme.flyoutRadius === 0 ? "Square" : Theme.flyoutRadius + " px"
                                }
                            }

                            SettingRow {
                                label: "Night light"
                                Toggle {
                                    checked: NightLight.enabled
                                    onToggled: NightLight.setEnabled(!NightLight.enabled)
                                }
                            }

                            SettingRow {
                                label: "Night light warmth"
                                opacity: NightLight.enabled ? 1 : 0.5
                                // Left is warmer: 6000K down to 2500K, like your old yad slider.
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: (6000 - NightLight.temperature) / 3500
                                    steps: 35
                                    onMoved: v => NightLight.setTemperature(Math.round((6000 - v * 3500) / 100) * 100)
                                }
                                ValueText {
                                    text: NightLight.temperature + "K"
                                }
                            }

                            SettingRow {
                                label: "Blur behind panels"
                                Toggle {
                                    checked: Settings.blur
                                    onToggled: Settings.blur = !Settings.blur
                                }
                            }

                            SettingRow {
                                label: "Blur strength"
                                opacity: Settings.blur ? 1 : 0.5
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.blurStrength / 100
                                    steps: 100
                                    onMoved: v => Settings.blurStrength = Math.round(v * 100)
                                }
                                ValueText {
                                    text: Settings.blurStrength
                                }
                            }

                            SettingRow {
                                label: "X-ray blur (blur only the wallpaper, not the windows behind)"
                                opacity: Settings.blur ? 1 : 0.5
                                Toggle {
                                    checked: Settings.blurXray
                                    onToggled: Settings.blurXray = !Settings.blurXray
                                }
                            }

                            // Blur strength is niri's setting: say so when niri's
                            // config doesn't include the file this writes.
                            Rectangle {
                                Layout.fillWidth: true
                                visible: !NiriBlur.included
                                Layout.preferredHeight: blurNote.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius / 1.5
                                color: Theme.overlay(Theme.surfaceContainerHigh, 0.8)

                                ColumnLayout {
                                    id: blurNote

                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingS

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "niri draws the blur, so the strength only takes effect once your niri config.kdl includes this line:"
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.Wrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingS

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: NiriBlur.includeLine
                                            font.family: Theme.monoFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideMiddle
                                        }

                                        IconButton {
                                            implicitHeight: 28
                                            icon: "content_copy"
                                            iconSize: 16
                                            text: "Copy"
                                            restColor: Theme.surfaceContainerHighest
                                            onClicked: Quickshell.execDetached(["wl-copy", "--", NiriBlur.includeLine])
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.topMargin: Theme.spacingM
                                text: "Surface tint"
                                font.pixelSize: Theme.fontSizeLarge
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Mixes a colour into the background of the taskbar, dock and every panel, and the fills inside them, so they aren't plain grey (with or without blur). Primary, secondary and tertiary are matugen's and follow the wallpaper."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            ColorSetting {
                                label: "Tint colour"
                                key: "surfaceTintColor"
                                customKey: "surfaceTintCustom"
                                options: ["primary", "secondary", "tertiary", "custom"]
                            }

                            SettingRow {
                                label: "Tint intensity"
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Theme.tintAmount
                                    steps: 100
                                    onMoved: v => Settings.surfaceTint = Math.round(v * 100) / 100
                                }
                                ValueText {
                                    text: Math.round(Theme.tintAmount * 100) + "%"
                                }
                            }

                            StyledText {
                                Layout.topMargin: Theme.spacingM
                                text: "Panel border"
                                font.pixelSize: Theme.fontSizeLarge
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "The outline of the flyouts, notepad, launcher, runner, clipboard history, notification pop-ups, OSD, dock and the other panels. The taskbar has none. The dock's border can be turned off on the Dock page."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            ColorSetting {
                                label: "Border colour"
                                key: "borderColor"
                                customKey: "borderColorCustom"
                                options: ["primary", "secondary", "tertiary", "outline", "text", "custom"]
                            }

                            SettingRow {
                                label: "Border opacity"
                                description: "0% hides the border."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Theme.blurBorder.a
                                    steps: 100
                                    onMoved: v => Settings.borderOpacity = Math.round(v * 100) / 100
                                }
                                ValueText {
                                    text: Math.round(Theme.blurBorder.a * 100) + "%"
                                }
                            }

                            SettingRow {
                                label: "Border on attached flyouts and notepad"
                                description: "When flyouts are attached to the taskbar, give the control center, calendar and notepad this border too. Floating, they always have it."
                                opacity: Settings.attachPanels ? 1 : 0.5
                                Toggle {
                                    checked: Settings.attachedPanelBorder
                                    onToggled: Settings.attachedPanelBorder = !Settings.attachedPanelBorder
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Theme.spacingXL
                        spacing: Theme.spacingM
                        visible: root.page === "clipboard"

                        StyledText {
                            text: "Clipboard"
                            font.pixelSize: Theme.fontSizeXLarge
                        }

                        SettingRow {
                            label: "Clear all also removes pinned items"
                            Toggle {
                                checked: Settings.clipboardClearPinned
                                onToggled: Settings.clipboardClearPinned = !Settings.clipboardClearPinned
                            }
                        }

                        SettingRow {
                            label: "Clear history at login"
                            Toggle {
                                checked: Settings.clipboardClearOnStartup
                                onToggled: Settings.clipboardClearOnStartup = !Settings.clipboardClearOnStartup
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Settings.clipboardClearPinned ? "Pinned items are removed by Clear all and at login." : "Pinned items are kept by Clear all and at login."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.spacingS
                            text: {
                                switch (ClipboardHistory.pasteMethod) {
                                case "wtype":
                                    return "Pasting types Ctrl+V into your app with wtype.";
                                default:
                                    return "wtype isn't installed, so choosing an entry only copies it; press Ctrl+V yourself. Pasting starts working once wtype is on your PATH.";
                                }
                            }
                            color: Theme.outline
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }

                    // Running apps on the taskbar: the settings page of the Better
                    // Running Apps plugin, with Taylor's values.
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.page === "taskbar"
                        contentHeight: taskbarColumn.implicitHeight + Theme.spacingXL * 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: taskbarColumn

                            x: Theme.spacingXL
                            y: Theme.spacingXL
                            width: parent.width - Theme.spacingXL * 2
                            spacing: Theme.spacingM

                            StyledText {
                                text: "Taskbar"
                                font.pixelSize: Theme.fontSizeXLarge
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Running apps: how app labels shrink when many windows are open, so the list doesn't run into the tray and clock."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                            }

                            SettingRow {
                                label: "Larger app icons"
                                description: "Use the large bar icon size."
                                Toggle {
                                    checked: Settings.runningAppsLargeIcons
                                    onToggled: Settings.runningAppsLargeIcons = !Settings.runningAppsLargeIcons
                                }
                            }

                            SettingRow {
                                label: "Current workspace only"
                                description: "Show only windows on the workspace you're looking at."
                                Toggle {
                                    checked: Settings.runningAppsCurrentWorkspaceOnly
                                    onToggled: Settings.runningAppsCurrentWorkspaceOnly = !Settings.runningAppsCurrentWorkspaceOnly
                                }
                            }

                            SettingRow {
                                label: "Group windows by app"
                                description: "Collapse each app's windows into one entry with a count badge."
                                Toggle {
                                    checked: Settings.runningAppsGroupByApp
                                    onToggled: Settings.runningAppsGroupByApp = !Settings.runningAppsGroupByApp
                                }
                            }

                            SettingRow {
                                label: "Max bar coverage"
                                description: "How much of the screen width running apps may fill before labels start shrinking."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: (Settings.runningAppsMaxWidthPercent - 30) / 70
                                    steps: 70
                                    onMoved: v => Settings.runningAppsMaxWidthPercent = Math.round(30 + v * 70)
                                }
                                ValueText {
                                    text: Settings.runningAppsMaxWidthPercent + "%"
                                }
                            }

                            SettingRow {
                                label: "Hard width cap"
                                description: "Absolute width limit. Off uses the percentage above instead."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.runningAppsMaxWidth / 4000
                                    steps: 400
                                    onMoved: v => Settings.runningAppsMaxWidth = Math.round(v * 400) * 10
                                }
                                ValueText {
                                    text: Settings.runningAppsMaxWidth === 0 ? "Off" : Settings.runningAppsMaxWidth + " px"
                                }
                            }

                            SettingRow {
                                label: "Full label width"
                                description: "Width of each app's label when there is plenty of room."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: (Settings.runningAppsFullTitleWidth - 40) / 260
                                    steps: 260
                                    onMoved: v => Settings.runningAppsFullTitleWidth = Math.round(40 + v * 260)
                                }
                                ValueText {
                                    text: Settings.runningAppsFullTitleWidth + " px"
                                }
                            }

                            SettingRow {
                                label: "Minimum label width"
                                description: "If a label would be narrower than this, the app shows as an icon only instead of a sliver of text. Off always shows labels."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.runningAppsMinTitleWidth / 200
                                    steps: 200
                                    onMoved: v => Settings.runningAppsMinTitleWidth = Math.round(v * 200)
                                }
                                ValueText {
                                    text: Settings.runningAppsMinTitleWidth === 0 ? "Off" : Settings.runningAppsMinTitleWidth + " px"
                                }
                            }

                            SettingRow {
                                label: "Reserved right-side space"
                                description: "Extra space to keep free when using the percentage. The taskbar already shrinks the list to fit, so 0 is usually fine."
                                StyledSlider {
                                    Layout.preferredWidth: 200
                                    value: Settings.runningAppsReservedWidth / 2000
                                    steps: 200
                                    onMoved: v => Settings.runningAppsReservedWidth = Math.round(v * 200) * 10
                                }
                                ValueText {
                                    text: Settings.runningAppsReservedWidth + " px"
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: Theme.spacingXL
                        spacing: Theme.spacingM
                        visible: root.page === "dock"

                        StyledText {
                            text: "Dock"
                            font.pixelSize: Theme.fontSizeXLarge
                        }

                        SettingRow {
                            label: "Show the dock"
                            Toggle {
                                checked: Settings.dockEnabled
                                onToggled: Settings.dockEnabled = !Settings.dockEnabled
                            }
                        }

                        SettingRow {
                            label: "Position"
                            Repeater {
                                model: ["left", "right"]

                                delegate: Rectangle {
                                    id: sideChip

                                    required property string modelData
                                    readonly property bool current: Settings.dockPosition === modelData

                                    implicitWidth: sideText.implicitWidth + Theme.spacingM * 2
                                    implicitHeight: 28
                                    radius: height / 2
                                    color: current ? Theme.primary : (sideMouse.containsMouse ? Theme.widgetHover : Theme.surfaceContainerHigh)

                                    StyledText {
                                        id: sideText
                                        anchors.centerIn: parent
                                        text: sideChip.modelData === "left" ? "Left" : "Right"
                                        color: sideChip.current ? Theme.onPrimary : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    MouseArea {
                                        id: sideMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Settings.dockPosition = sideChip.modelData
                                    }
                                }
                            }
                        }

                        SettingRow {
                            label: "Hide until the pointer reaches the screen edge"
                            Toggle {
                                checked: Settings.dockAutoHide
                                onToggled: Settings.dockAutoHide = !Settings.dockAutoHide
                            }
                        }

                        SettingRow {
                            label: "Border"
                            Toggle {
                                checked: Settings.dockBorder
                                onToggled: Settings.dockBorder = !Settings.dockBorder
                            }
                        }

                        // Sliders map 0..1 onto each setting's range.
                        SettingRow {
                            label: "Icon size"
                            StyledSlider {
                                Layout.preferredWidth: 200
                                value: (Settings.dockIconSize - 20) / 36
                                steps: 36
                                onMoved: v => Settings.dockIconSize = Math.round(20 + v * 36)
                            }
                            ValueText {
                                text: Settings.dockIconSize + " px"
                            }
                        }

                        SettingRow {
                            label: "Spacing"
                            StyledSlider {
                                Layout.preferredWidth: 200
                                value: (Settings.dockSpacing - 2) / 14
                                steps: 14
                                onMoved: v => Settings.dockSpacing = Math.round(2 + v * 14)
                            }
                            ValueText {
                                text: Settings.dockSpacing + " px"
                            }
                        }

                        StyledText {
                            Layout.topMargin: Theme.spacingS
                            text: "Pinned apps (right-click an app in the dock, launcher or taskbar to pin it)"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        ListView {
                            id: pinList

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: Settings.dockPins

                            delegate: Rectangle {
                                id: pinRow

                                required property string modelData
                                required property int index

                                width: ListView.view.width
                                height: 36
                                radius: Theme.cornerRadius / 1.5
                                color: pinHover.hovered ? Theme.surfaceContainerHigh : "transparent"

                                HoverHandler {
                                    id: pinHover
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingXS
                                    spacing: Theme.spacingS

                                    IconImage {
                                        implicitSize: 22
                                        source: Apps.iconFor(pinRow.modelData)
                                        asynchronous: true
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Apps.nameFor(pinRow.modelData)
                                        elide: Text.ElideRight
                                    }

                                    IconButton {
                                        implicitHeight: 28
                                        icon: "keyboard_arrow_up"
                                        contentColor: Theme.surfaceVariantText
                                        opacity: pinRow.index > 0 ? 1 : 0.3
                                        onClicked: DockApps.movePin(pinRow.modelData, -1)
                                    }
                                    IconButton {
                                        implicitHeight: 28
                                        icon: "keyboard_arrow_down"
                                        contentColor: Theme.surfaceVariantText
                                        opacity: pinRow.index < pinList.count - 1 ? 1 : 0.3
                                        onClicked: DockApps.movePin(pinRow.modelData, 1)
                                    }
                                    IconButton {
                                        implicitHeight: 28
                                        icon: "close"
                                        contentColor: Theme.surfaceVariantText
                                        onClicked: DockApps.unpin(pinRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A label on the left, its controls (the children) on the right.
    // An optional description goes in small text under the label.
    component SettingRow: RowLayout {
        property alias label: rowLabel.text
        property alias description: rowDescription.text

        Layout.fillWidth: true
        spacing: Theme.spacingM

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                id: rowLabel
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }

            StyledText {
                id: rowDescription
                Layout.fillWidth: true
                visible: text !== ""
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
        }
    }

    // A colour setting: chips for matugen's colours (with a swatch each) and
    // Custom, which shows a #rrggbb field and a "Pick" button using niri's
    // colour picker. `key` holds the choice, `customKey` the custom hex.
    component ColorSetting: ColumnLayout {
        id: colorSetting

        required property string key
        required property string customKey
        property string label
        property var options: ["primary", "secondary", "tertiary", "custom"]
        readonly property var titles: ({
                "primary": "Primary",
                "secondary": "Secondary",
                "tertiary": "Tertiary",
                "outline": "Outline",
                "text": "Text",
                "custom": "Custom"
            })
        readonly property string customHex: Settings[customKey] ?? ""

        Layout.fillWidth: true
        spacing: Theme.spacingS

        StyledText {
            Layout.fillWidth: true
            text: colorSetting.label
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Repeater {
                model: colorSetting.options

                delegate: Rectangle {
                    id: chip

                    required property string modelData
                    readonly property bool current: (Settings[colorSetting.key] || "primary") === modelData

                    width: chipRow.implicitWidth + Theme.spacingM * 2
                    height: 28
                    radius: height / 2
                    color: current ? Theme.withAlpha(Theme.primary, 0.25) : (chipMouse.containsMouse ? Theme.widgetHover : Theme.surfaceContainerHigh)
                    border.width: current ? 1 : 0
                    border.color: Theme.primary

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 6
                            color: chip.modelData === "custom" && !Theme.isHexColor(colorSetting.customHex) ? "transparent" : Theme.namedColor(chip.modelData, colorSetting.customHex)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.5)
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: colorSetting.titles[chip.modelData] ?? chip.modelData
                            color: chip.current ? Theme.surfaceText : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings[colorSetting.key] = chip.modelData
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Settings[colorSetting.key] === "custom"
            spacing: Theme.spacingM

            StyledText {
                Layout.fillWidth: true
                text: "Custom colour (#rrggbb)"
                color: Theme.surfaceVariantText
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Theme.isHexColor(colorSetting.customHex) ? Theme.normalizeHex(colorSetting.customHex) : "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.6)
            }

            CommandField {
                key: colorSetting.customKey
                Layout.fillWidth: false
                Layout.preferredWidth: 110
            }

            IconButton {
                icon: "colorize"
                iconSize: 18
                text: "Pick"
                restColor: Theme.surfaceContainerHigh
                onClicked: picker.running = true

                Tooltip {
                    target: parent
                    shown: parent.hovered
                    text: "Pick a colour from the screen"
                }
            }
        }

        Process {
            id: picker
            command: ["niri", "msg", "pick-color"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const hex = text.match(/#[0-9a-fA-F]{6}/);
                    if (hex)
                        Settings[colorSetting.customKey] = hex[0].toLowerCase();
                }
            }
        }
    }

    component ValueText: StyledText {
        Layout.preferredWidth: 48
        horizontalAlignment: Text.AlignRight
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }

    component CommandLabel: Row {
        property string icon
        property alias text: label.text

        Layout.preferredWidth: 110
        spacing: Theme.spacingS

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: parent.icon
            size: 18
            color: Theme.surfaceVariantText
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceVariantText
        }
    }

    // A text field bound to one Settings property.
    component CommandField: Rectangle {
        id: field

        required property string key

        Layout.fillWidth: true
        Layout.preferredHeight: 38
        radius: Theme.cornerRadius / 1.5
        color: Theme.surface
        border.width: 1
        border.color: input.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.surfaceText
            selectionColor: Theme.primarySelected
            selectedTextColor: Theme.surfaceText
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontSizeSmall + 1
            selectByMouse: true
            clip: true

            // Not a binding: typing would break it. Settings changes made
            // elsewhere (Reset, or editing settings.json) are pushed in below.
            Component.onCompleted: {
                text = Settings[field.key];
                cursorPosition = 0;
            }
            onTextChanged: {
                if (text !== Settings[field.key])
                    Settings[field.key] = text;
            }

            Connections {
                target: Settings
                function onLockCommandChanged() {
                    input.sync();
                }
                function onSleepCommandChanged() {
                    input.sync();
                }
                function onRestartCommandChanged() {
                    input.sync();
                }
                function onShutdownCommandChanged() {
                    input.sync();
                }
                function onWallpaperFolderChanged() {
                    input.sync();
                }
                function onSurfaceTintCustomChanged() {
                    input.sync();
                }
                function onBorderColorCustomChanged() {
                    input.sync();
                }
            }

            function sync() {
                if (text !== Settings[field.key])
                    text = Settings[field.key];
            }
        }
    }

    // A font setting: the current font (shown in itself) opens a list of
    // every installed family to search and pick from, each shown in itself.
    component FontSetting: ColumnLayout {
        id: fontSetting

        required property string key
        property string label
        property string description
        property bool open: false
        property string query: ""
        readonly property string current: Settings[key] ?? ""
        readonly property var families: open ? Qt.fontFamilies() : []
        readonly property var matches: {
            const q = query.trim().toLowerCase();
            return q === "" ? families : families.filter(f => f.toLowerCase().includes(q));
        }

        Layout.fillWidth: true
        spacing: Theme.spacingS

        SettingRow {
            label: fontSetting.label
            description: fontSetting.description

            Rectangle {
                implicitWidth: 220
                implicitHeight: 34
                radius: Theme.cornerRadius / 1.5
                color: Theme.surface
                border.width: 1
                border.color: fontSetting.open ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)

                StyledText {
                    anchors.left: parent.left
                    anchors.right: chevron.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: fontSetting.current
                    font.family: fontSetting.current
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    id: chevron
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    name: fontSetting.open ? "expand_less" : "expand_more"
                    size: 18
                    color: Theme.surfaceVariantText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        fontSetting.open = !fontSetting.open;
                        fontSetting.query = "";
                        if (fontSetting.open)
                            fontSearch.forceActiveFocus();
                    }
                }
            }

            ResetButton {
                key: fontSetting.key
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            visible: fontSetting.open
            radius: Theme.cornerRadius / 1.5
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 1)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.4)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadius / 2
                    color: Theme.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        MaterialIcon {
                            name: "search"
                            size: 16
                            color: Theme.surfaceVariantText
                        }

                        TextInput {
                            id: fontSearch
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.surfaceText
                            selectionColor: Theme.primarySelected
                            font.family: Theme.fontFamily
                            font.weight: Theme.fontWeight
                            font.pixelSize: 13
                            clip: true
                            onTextChanged: fontSetting.query = text
                            Keys.onEscapePressed: fontSetting.open = false
                            onAccepted: {
                                if (fontSetting.matches.length > 0) {
                                    Settings[fontSetting.key] = fontSetting.matches[0];
                                    fontSetting.open = false;
                                }
                            }

                            StyledText {
                                anchors.fill: parent
                                visible: fontSearch.text === ""
                                text: "Search fonts"
                                color: Theme.withAlpha(Theme.surfaceText, 0.4)
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                ListView {
                    id: fontList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: fontSetting.matches

                    delegate: Rectangle {
                        id: fontRow

                        required property string modelData
                        readonly property bool selected: modelData === fontSetting.current

                        width: ListView.view.width
                        height: 32
                        radius: Theme.cornerRadius / 2
                        color: selected ? Theme.withAlpha(Theme.primary, 0.2) : (rowMouse.containsMouse ? Theme.widgetHover : "transparent")

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: fontRow.modelData
                            font.family: fontRow.modelData
                            color: fontRow.selected ? Theme.primary : Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Settings[fontSetting.key] = fontRow.modelData;
                                fontSetting.open = false;
                            }
                        }
                    }
                }
            }
        }
    }

    component ResetButton: IconButton {
        required property string key

        icon: "undo"
        iconSize: 18
        contentColor: Theme.surfaceVariantText
        opacity: Settings[key] === Settings.defaults[key] ? 0.35 : 1
        onClicked: Settings.reset(key)

        Tooltip {
            target: parent
            shown: parent.hovered
            text: "Reset to default"
        }
    }
}
