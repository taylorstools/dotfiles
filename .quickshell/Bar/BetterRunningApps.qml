import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Port of Taylor's old BetterRunningApps plugin. Same adaptive-width behaviour:
// every app shows its title, the title area shrinks (and elides) as more
// windows open so the strip stays inside its budget, and below
// minTitleWidth the pills drop to icon-only.
//
// What changed from the plugin:
//  - Windows come straight from niri's IPC (Services/Niri.qml) instead of
//    a compositor service, ordered by layout (workspace, column, row).
//  - The bar passes the space it actually has free in allottedPrimarySize,
//    so the strip shrinks against the real layout, not just the settings.
//  - Settings live in Common/Settings.qml (Shell Settings > Taskbar) instead
//    of plugin_settings.json.
//  - Horizontal bar only (the vertical column layout was dropped).
Item {
    id: root

    property var parentScreen: null
    property real barThickness: Theme.barThickness
    property real widgetThickness: Theme.widgetThickness
    property var hoveredItem: null

    // Free space the bar can give this widget. <= 0 means "unknown".
    property real allottedPrimarySize: 0

    readonly property real horizontalPadding: 2   // with no pill background

    // Tunables (Shell Settings > Taskbar)
    readonly property real appIconSize: Theme.barIconSize(barThickness, Settings.runningAppsLargeIcons)
    readonly property bool groupByApp: Settings.runningAppsGroupByApp
    readonly property bool currentWorkspaceOnly: Settings.runningAppsCurrentWorkspaceOnly

    property real fullTitleWidth: Settings.runningAppsFullTitleWidth       // title area width when there is plenty of room
    property real minTitleWidth: Settings.runningAppsMinTitleWidth         // below this label width, pills drop to icon-only instead of a tiny slice
    property real maxRunningAppsWidth: Settings.runningAppsMaxWidth > 0 ? Settings.runningAppsMaxWidth : -1  // hard cap (px); <= 0 falls back to maxWidthFraction
    property real maxWidthFraction: (Number(Settings.runningAppsMaxWidthPercent) || 100) / 100  // fraction of the screen width running apps may occupy before shrinking
    property real reservedBarWidth: Settings.runningAppsReservedWidth      // additional px to subtract from the budget

    readonly property real itemSpacing: 3
    // The focus underline along each pill's bottom edge. The icon and title
    // sit near the middle of the part of the pill above it: centred exactly
    // they looked a little high, so 1px lower (Taylor's call).
    readonly property real underlineHeight: 3
    readonly property real contentOffset: Theme.snap(-underlineHeight / 2 + 1)
    readonly property real iconAreaWidth: 24 + Theme.spacingXS
    readonly property real iconOnlyWidth: 24

    // Window data

    readonly property var sortedWindows: {
        const all = Niri.sortedWindows;
        if (!currentWorkspaceOnly)
            return all;
        const wsId = Niri.activeWorkspaceId(parentScreen ? parentScreen.name : "");
        return all.filter(w => w.workspace_id === wsId);
    }

    readonly property var groupedWindows: {
        if (!groupByApp)
            return [];
        const groups = new Map();
        for (const w of sortedWindows) {
            const appId = w.app_id || "unknown";
            if (!groups.has(appId))
                groups.set(appId, {
                    "appId": appId,
                    "windows": []
                });
            groups.get(appId).windows.push(w);
        }
        return Array.from(groups.values());
    }

    readonly property string focusedAppId: {
        const w = sortedWindows.find(win => win.is_focused);
        return w ? (w.app_id || "") : "";
    }

    readonly property int windowCount: groupByApp ? groupedWindows.length : sortedWindows.length

    // The Repeater is keyed by plain ids (window ids, or app ids when
    // grouped) so delegates survive title/focus changes; each delegate looks
    // its live data up by key.
    readonly property var modelKeys: groupByApp ? groupedWindows.map(g => g.appId) : sortedWindows.map(w => w.id)

    function groupFor(appId) {
        return groupedWindows.find(g => g.appId === appId) ?? null;
    }

    // Adaptive width

    readonly property real availableWidth: {
        if (maxRunningAppsWidth > 0)
            return maxRunningAppsWidth;
        const screenW = parentScreen ? parentScreen.width : 0;
        if (screenW <= 0)
            return -1; // unknown: don't shrink
        return screenW * maxWidthFraction - reservedBarWidth;
    }

    function titleBudgetFor(budget) {
        if (windowCount === 0)
            return 0;
        if (budget <= 0)
            return fullTitleWidth;
        const fixed = (windowCount - 1) * itemSpacing + horizontalPadding * 2;
        return (budget - fixed) / windowCount - iconAreaWidth;
    }

    function stripSizeFor(budget) {
        if (windowCount === 0)
            return 0;
        const rawTitle = titleBudgetFor(budget);
        const perApp = rawTitle >= minTitleWidth ? (iconAreaWidth + Math.min(fullTitleWidth, Math.max(0, rawTitle))) : iconOnlyWidth;
        return Math.round(windowCount * perApp + (windowCount - 1) * itemSpacing + horizontalPadding * 2);
    }

    // The settings budget is a ceiling; the bar's allotment can only tighten it.
    readonly property real layoutBudget: {
        if (allottedPrimarySize <= 0)
            return availableWidth;
        return availableWidth > 0 ? Math.min(availableWidth, allottedPrimarySize) : allottedPrimarySize;
    }

    readonly property real rawTitleBudget: titleBudgetFor(layoutBudget)
    readonly property bool labelsVisible: windowCount > 0 && rawTitleBudget >= minTitleWidth
    readonly property real effectiveTitleWidth: labelsVisible ? Math.min(fullTitleWidth, Math.max(0, rawTitleBudget)) : 0
    readonly property real perAppWidth: labelsVisible ? (iconAreaWidth + effectiveTitleWidth) : iconOnlyWidth
    readonly property int calculatedSize: stripSizeFor(layoutBudget)

    implicitWidth: windowCount > 0 ? calculatedSize : 0
    implicitHeight: barThickness
    width: implicitWidth
    height: implicitHeight
    visible: windowCount > 0

    // Scroll through windows, mouse wheel or touchpad.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        property real scrollAccumulator: 0
        readonly property real touchpadThreshold: 500

        function step(direction) {
            const windows = root.sortedWindows;
            if (windows.length < 2)
                return;
            const current = windows.findIndex(w => w.is_focused);
            let next;
            if (direction < 0)
                next = current === -1 ? 0 : Math.min(current + 1, windows.length - 1);
            else
                next = current === -1 ? windows.length - 1 : Math.max(current - 1, 0);
            Niri.focusWindow(windows[next].id);
        }

        onWheel: wheel => {
            const deltaY = wheel.angleDelta.y;
            const isMouseWheel = Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0;
            if (isMouseWheel) {
                step(deltaY);
            } else {
                scrollAccumulator += deltaY;
                if (Math.abs(scrollAccumulator) >= touchpadThreshold) {
                    step(scrollAccumulator);
                    scrollAccumulator = 0;
                }
            }
            wheel.accepted = true;
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.itemSpacing

        Repeater {
            model: root.modelKeys

            delegate: Item {
                id: delegateItem

                required property var modelData

                readonly property bool isGrouped: root.groupByApp
                readonly property var groupData: isGrouped ? root.groupFor(modelData) : null
                readonly property var windowData: isGrouped ? (groupData && groupData.windows.length > 0 ? groupData.windows[0] : null) : (Niri.windows[modelData] ?? null)
                readonly property string appId: isGrouped ? String(modelData) : (windowData ? (windowData.app_id || "") : "")
                readonly property bool isFocused: isGrouped ? (root.focusedAppId === appId) : (windowData ? windowData.is_focused : false)
                readonly property string windowTitle: windowData ? (windowData.title || "(Unnamed)") : "(Unnamed)"
                readonly property int groupCount: isGrouped && groupData ? groupData.windows.length : 1
                readonly property string appName: Apps.nameFor(appId)
                readonly property string tooltipText: {
                    if (isGrouped && groupCount > 1)
                        return appName + " (" + groupCount + " windows)";
                    return appName + (windowTitle ? " • " + windowTitle : "");
                }
                readonly property real visualWidth: root.perAppWidth

                implicitWidth: visualWidth
                width: visualWidth
                height: root.barThickness

                function activate() {
                    if (isGrouped && groupCount > 1) {
                        const wins = groupData.windows;
                        const current = wins.findIndex(w => w.is_focused);
                        Niri.focusWindow(wins[(current + 1) % wins.length].id);
                    } else if (windowData) {
                        Niri.focusWindow(windowData.id);
                    }
                }

                Rectangle {
                    id: visualContent
                    anchors.fill: parent
                    color: {
                        if (delegateItem.isFocused)
                            return mouseArea.containsMouse ? Theme.primarySelected : Theme.withAlpha(Theme.primary, 0.2);
                        return mouseArea.containsMouse ? Theme.widgetHover : "transparent";
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.underlineHeight
                        color: delegateItem.isFocused ? Theme.primary : Theme.withAlpha(Theme.primary, 0.2)
                    }

                    IconImage {
                        id: iconImg
                        anchors.left: parent.left
                        anchors.leftMargin: root.labelsVisible ? Theme.spacingXS : Math.max(0, (delegateItem.visualWidth - width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: root.contentOffset
                        implicitSize: root.appIconSize
                        source: Apps.iconFor(delegateItem.appId)
                        asynchronous: true
                        visible: status === Image.Ready
                    }

                    MaterialIcon {
                        anchors.centerIn: iconImg
                        size: root.appIconSize
                        name: "sports_esports"
                        visible: !iconImg.visible && Apps.isSteamApp(delegateItem.appId)
                    }

                    // Initial-letter fallback, centred on the icon slot (not the
                    // whole pill, which would draw it over the title).
                    Text {
                        anchors.horizontalCenter: iconImg.horizontalCenter
                        anchors.verticalCenter: iconImg.verticalCenter
                        visible: !iconImg.visible && !Apps.isSteamApp(delegateItem.appId)
                        text: delegateItem.appId ? delegateItem.appName.charAt(0).toUpperCase() : "?"
                        font.family: Theme.fontFamily
                        font.weight: Theme.fontWeight
                        font.pixelSize: 10
                        color: Theme.widgetText
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -2
                        anchors.bottomMargin: -2
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.primary
                        visible: delegateItem.isGrouped && delegateItem.groupCount > 1
                        z: 10

                        StyledText {
                            anchors.centerIn: parent
                            text: delegateItem.groupCount > 9 ? "9+" : delegateItem.groupCount
                            font.pixelSize: 9
                            color: Theme.surface
                        }
                    }

                    StyledText {
                        anchors.left: iconImg.right
                        anchors.leftMargin: Theme.spacingXS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: iconImg.verticalCenter
                        visible: root.labelsVisible
                        text: delegateItem.windowTitle
                        font.pixelSize: Theme.barTextSize(root.barThickness)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            delegateItem.activate();
                        } else if (mouse.button === Qt.RightButton) {
                            root.hoveredItem = null;
                            contextMenu.open(delegateItem, delegateItem.windowData);
                        } else if (mouse.button === Qt.MiddleButton && delegateItem.windowData) {
                            Niri.closeWindow(delegateItem.windowData.id);
                        }
                    }
                    onEntered: root.hoveredItem = delegateItem
                    onExited: {
                        if (root.hoveredItem === delegateItem)
                            root.hoveredItem = null;
                    }
                }

                Tooltip {
                    target: delegateItem
                    text: delegateItem.tooltipText
                    shown: root.hoveredItem === delegateItem && !contextMenu.isOpen
                }
            }
        }
    }

    // Right-click menu: pin the app to the dock, or close the window (the
    // plugin's menu only had Close). It dismisses itself once the pointer
    // leaves it.
    Item {
        id: contextMenu

        property Item anchorItem: null
        property var windowData: null
        property bool menuHovered: false
        readonly property bool isOpen: anchorItem !== null

        function open(item, data) {
            windowData = data;
            anchorItem = item;
            leaveTimer.restart();
        }

        function close() {
            anchorItem = null;
            windowData = null;
            menuHovered = false;
        }

        Timer {
            id: leaveTimer
            interval: 1500
            onTriggered: {
                if (!contextMenu.menuHovered)
                    contextMenu.close();
            }
        }

        Loader {
            active: contextMenu.isOpen
            sourceComponent: BarPopup {
                target: contextMenu.anchorItem
                padding: Theme.spacingXS
                visible: true

                Column {
                    readonly property string appId: DockApps.idForAppId(contextMenu.windowData?.app_id ?? "")
                    readonly property bool pinned: DockApps.isPinned(appId)

                    width: 140

                    HoverHandler {
                        onHoveredChanged: {
                            contextMenu.menuHovered = hovered;
                            if (!hovered)
                                leaveTimer.restart();
                        }
                    }

                    MenuRow {
                        text: parent.pinned ? "Unpin from dock" : "Pin to dock"
                        onClicked: {
                            DockApps.togglePin(parent.appId);
                            contextMenu.close();
                        }
                    }

                    MenuRow {
                        text: "Close"
                        onClicked: {
                            if (contextMenu.windowData)
                                Niri.closeWindow(contextMenu.windowData.id);
                            contextMenu.close();
                        }
                    }
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: menuRow

        property string text

        signal clicked

        width: 140
        height: 32
        radius: Theme.cornerRadius - Theme.spacingXS
        color: rowArea.containsMouse ? Theme.widgetHover : "transparent"

        StyledText {
            anchors.centerIn: parent
            text: menuRow.text
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRow.clicked()
        }
    }
}
