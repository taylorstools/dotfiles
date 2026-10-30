import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Notifications
import qs.Services
import qs.Wallpaper
import qs.Widgets

// The flyout behind the bar's clock, with tabs along the bottom:
//   Overview       the time to the second, the date and a six-week calendar
//                  laid out like the Windows 10 one
//   Notifications  everything not dismissed yet, do not disturb, clear all
//   Wallpapers     the same picker as the settings window
// Click the clock, or
//   qs ipc -p <this folder> call clock toggle
// Esc or a click outside closes it.
Scope {
    id: root

    readonly property bool shown: Popouts.clockScreen !== null
    // Months away from the current one, for the calendar's up/down buttons.
    property int monthOffset: 0

    readonly property date shownMonth: {
        const now = clock.date;
        return new Date(now.getFullYear(), now.getMonth() + monthOffset, 1);
    }
    // 42 days starting on the Sunday on or before the 1st.
    readonly property var calendarDays: {
        const first = shownMonth;
        const start = new Date(first.getFullYear(), first.getMonth(), 1 - first.getDay());
        const days = [];
        for (let i = 0; i < 42; i++)
            days.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return days;
    }

    function close() {
        Popouts.clockScreen = null;
    }

    onShownChanged: {
        if (shown) {
            window.screen = Popouts.clockScreen;
            monthOffset = 0;
        }
    }

    SystemClock {
        id: clock
        precision: root.shown ? SystemClock.Seconds : SystemClock.Minutes
    }

    IpcHandler {
        target: "clock"

        function toggle(): void {
            if (root.shown) {
                root.close();
                return;
            }
            const screens = Array.from(Quickshell.screens);
            Popouts.toggleClock(screens.find(s => s.name === Niri.focusedOutput) ?? screens[0]);
        }
        // overview, notifications or wallpapers
        function open(tab: string): void {
            Popouts.clockTab = tab;
            if (!root.shown)
                toggle();
        }
        function close(): void {
            root.close();
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
        // Covers the screen above the bar, so clicks on the bar still reach it.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"

        WlrLayershell.namespace: "qstest:clock"
        WlrLayershell.layer: WlrLayer.Top
        // Exclusive, like the control center: with on-demand focus, a press on
        // the bar takes the keyboard away from the flyout, the shell has no
        // focused window for a moment, and Qt cancels the press - so clicking
        // another bar button while this was open needed a second click.
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                applyBlur();
        }

        Item {
            // Follows the panel as it rises out of the bar. Kept inside the
            // window: attached, the panel reaches past its bottom and right.
            Region {
                id: blurRegion
                x: panel.x
                y: panel.y + (1 - motion.progress) * 16
                width: panel.width
                height: panel.height

                Region {
                    intersection: Intersection.Intersect
                    width: window.width
                    height: window.height
                }
            }
        }

        // Re-apply when blur is switched in the settings window, or the panel
        // changes shape (corner radius).
        Connections {
            target: Settings
            function onBlurChanged() {
                window.applyBlur();
            }
            // Later, once panel.radius has caught up.
            function onAttachPanelsChanged() {
                Qt.callLater(window.applyBlur);
            }
            function onFlyoutRadiusChanged() {
                Qt.callLater(window.applyBlur);
            }
        }

        function applyBlur() {
            // Region.radius only exists in newer Quickshell builds.
            if ("radius" in blurRegion)
                blurRegion.radius = panel.radius;
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
        }

        Shortcut {
            sequences: ["Escape"]
            enabled: root.shown
            onActivated: root.close()
        }

        // Click outside the panel closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: panel

            // Fades in while rising out of the bar; Settings > Appearance sets the speed.
            opacity: motion.progress
            transform: Translate {
                y: (1 - motion.progress) * 16
            }

            // Attached: reaches Theme.flyoutOvershoot past the taskbar and the
            // screen edge, so only the top-left corner is rounded and only the
            // top and left borders show. The content keeps clear of that strip.
            readonly property real overshoot: Theme.flyoutOvershoot

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.attachPanels ? -overshoot : Theme.spacingS
            width: Config.clockFlyoutWidth + overshoot
            height: Config.clockFlyoutHeight + overshoot
            radius: Theme.flyoutRadius
            color: Theme.popupBackground
            border.width: Theme.edgePanelBorder ? 1 : 0
            border.color: Theme.blurBorder

            // Swallows clicks so they don't close the panel.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                anchors.rightMargin: 14 + panel.overshoot
                anchors.bottomMargin: 14 + panel.overshoot
                spacing: 12

                // Overview
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Popouts.clockTab === "overview"
                    spacing: 10

                    Row {
                        Layout.leftMargin: 4
                        spacing: 8

                        Text {
                            id: timeText
                            // Qt only counts h as 12-hour when AP is in the same format string.
                            text: Config.use24HourClock ? Qt.formatTime(clock.date, "HH:mm:ss") : Qt.formatTime(clock.date, "h:mm:ss AP").split(" ")[0]
                            color: Theme.surfaceText
                            // The shell font, lighter for the big clock.
                            font.family: Theme.fontFamily
                            font.weight: Font.Light
                            font.pixelSize: 44
                        }

                        StyledText {
                            anchors.baseline: timeText.baseline
                            visible: !Config.use24HourClock
                            text: Qt.formatTime(clock.date, "AP")
                            color: Theme.surfaceVariantText
                            font.pixelSize: 18
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 4
                        Layout.topMargin: -6
                        text: Qt.formatDate(clock.date, "dddd, MMMM d, yyyy")
                        color: Theme.primary
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.topMargin: 4
                        color: Theme.surfaceContainerHighest
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: 2

                        // Click the month to jump back to today.
                        StyledText {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.shownMonth, "MMMM yyyy")

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: root.monthOffset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.monthOffset = 0
                            }
                        }

                        IconButton {
                            icon: "keyboard_arrow_up"
                            contentColor: Theme.surfaceVariantText
                            onClicked: root.monthOffset--
                        }

                        IconButton {
                            icon: "keyboard_arrow_down"
                            contentColor: Theme.surfaceVariantText
                            onClicked: root.monthOffset++
                        }
                    }

                    // A plain Grid with fixed cell sizes; GridLayout spread the
                    // columns unevenly by text width.
                    Grid {
                        id: calendarGrid

                        readonly property real cellWidth: width / 7
                        readonly property real cellHeight: (height - 24) / 6

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 7

                        Repeater {
                            model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

                            delegate: StyledText {
                                required property string modelData

                                width: calendarGrid.cellWidth
                                height: 24
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: Theme.outline
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Repeater {
                            model: root.calendarDays

                            delegate: Item {
                                id: day

                                required property var modelData
                                readonly property bool today: modelData.toDateString() === clock.date.toDateString()
                                readonly property bool inMonth: modelData.getMonth() === root.shownMonth.getMonth()

                                width: calendarGrid.cellWidth
                                height: calendarGrid.cellHeight

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: day.today ? Theme.primary : "transparent"
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: day.modelData.getDate()
                                    color: day.today ? Theme.onPrimary : (day.inMonth ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.35))
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                }

                // Notifications
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Popouts.clockTab === "notifications"
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: "Notifications"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        // Do not disturb: a red bell with a slash while it's on.
                        IconButton {
                            implicitHeight: 28
                            icon: Notifications.dnd ? "notifications_off" : "notifications"
                            iconSize: 17
                            contentColor: Notifications.dnd ? Theme.error : Theme.surfaceText
                            restColor: Notifications.dnd ? Theme.withAlpha(Theme.error, 0.18) : Theme.surfaceContainerHigh
                            onClicked: Notifications.toggleDnd()

                            Tooltip {
                                target: parent
                                shown: parent.hovered
                                text: Notifications.dnd ? "Do not disturb is on" : "Do not disturb"
                            }
                        }

                        IconButton {
                            implicitHeight: 28
                            text: "Clear all"
                            restColor: Theme.surfaceContainerHigh
                            visible: Notifications.list.length > 0
                            onClicked: Notifications.clearAll()
                        }
                    }

                    ListView {
                        id: notificationList

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel {
                            values: Notifications.list
                        }

                        delegate: NotificationCard {
                            required property var modelData

                            width: ListView.view.width
                            notification: modelData
                        }

                        Column {
                            anchors.centerIn: parent
                            visible: notificationList.count === 0
                            spacing: 8

                            MaterialIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: "notifications_off"
                                size: 36
                                color: Theme.outline
                            }

                            StyledText {
                                text: "You're all caught up"
                                color: Theme.outline
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                // Wallpapers
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Popouts.clockTab === "wallpapers"
                    spacing: 8

                    IconButton {
                        Layout.alignment: Qt.AlignRight
                        implicitHeight: 28
                        icon: "shuffle"
                        iconSize: 17
                        text: "Random"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: Wallpaper.random()
                    }

                    WallpaperPicker {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        SegmentButton {
                            icon: "calendar_month"
                            text: "Overview"
                            current: Popouts.clockTab === "overview"
                            onClicked: Popouts.clockTab = "overview"
                        }
                        SegmentButton {
                            icon: "notifications"
                            text: "Notifications"
                            current: Popouts.clockTab === "notifications"
                            onClicked: Popouts.clockTab = "notifications"
                        }
                        SegmentButton {
                            icon: "wallpaper"
                            text: "Wallpapers"
                            current: Popouts.clockTab === "wallpapers"
                            onClicked: Popouts.clockTab = "wallpapers"
                        }
                    }
                }
            }
        }
    }
}
