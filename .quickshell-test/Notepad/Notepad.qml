import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Notepad that slides in from the right edge, like DMS's notepad slideout.
//   qs ipc -p <this folder> call notepad toggle      (or ./run.sh notepad)
// Text is written to disk shortly after you stop typing, for scratch tabs and
// opened files alike. Esc closes, Ctrl+S saves (asks for a path on a scratch
// tab), Ctrl+O opens, Ctrl+N / Ctrl+W add and close tabs, Ctrl+Tab and
// Ctrl+Shift+Tab switch. Double-click a scratch tab to rename it, middle-click
// to close it. Opens on the monitor niri has focused.
Scope {
    id: root

    property bool shown: false
    // Stays true until the slide-out animation has finished.
    property bool mapped: false
    property bool expanded: false

    // What's on disk for the current tab, so we know when there's something to save.
    property string savedText: ""
    property bool loadingText: false
    readonly property bool dirty: editor.text !== savedText
    property string errorText: ""

    // "save" or "open" while the path field is showing.
    property string pathPrompt: ""
    // A Save As target that already exists; a second Enter replaces it.
    property string confirmOverwritePath: ""
    property int renamingIndex: -1

    function show() {
        if (!mapped) {
            const screens = Array.from(Quickshell.screens);
            const target = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
            if (target)
                window.screen = target;
        }
        mapped = true;
        shown = true;
        editor.forceActiveFocus();
    }

    function hide() {
        if (!shown)
            return;
        flush();
        rememberPosition();
        closePrompt();
        renamingIndex = -1;
        shown = false;
    }

    function toggle() {
        if (shown)
            hide();
        else
            show();
    }

    function flush() {
        saveTimer.stop();
        if (!NotepadStore.ready || loadingText || !dirty)
            return;
        savedText = editor.text;
        contentFile.setText(editor.text);
    }

    function rememberPosition() {
        if (NotepadStore.ready)
            NotepadStore.updateTab(NotepadStore.currentIndex, {
                cursorPosition: editor.cursorPosition,
                scrollPosition: flick.contentY
            });
    }

    function loadText(text) {
        loadingText = true;
        savedText = text;
        editor.text = text;
        loadingText = false;
        const tab = NotepadStore.currentTab;
        editor.cursorPosition = Math.min(tab?.cursorPosition ?? 0, editor.length);
        Qt.callLater(() => {
            flick.contentY = Math.max(0, Math.min(tab?.scrollPosition ?? 0, flick.contentHeight - flick.height));
        });
    }

    function switchTab(index) {
        flush();
        rememberPosition();
        NotepadStore.switchTo(index);
        editor.forceActiveFocus();
    }

    function cycleTab(step) {
        const count = NotepadStore.tabs.length;
        if (count > 1)
            switchTab((NotepadStore.currentIndex + step + count) % count);
    }

    function newTab() {
        flush();
        rememberPosition();
        NotepadStore.addTab();
        editor.forceActiveFocus();
    }

    function closeTab(index) {
        flush();
        NotepadStore.closeTab(index);
        editor.forceActiveFocus();
    }

    function finishRename(index, title) {
        if (renamingIndex !== index)
            return;
        renamingIndex = -1;
        const trimmed = title.trim();
        if (trimmed !== "")
            NotepadStore.updateTab(index, {
                title: trimmed
            });
        editor.forceActiveFocus();
    }

    // Scratch tabs need a path first; opened files are just written now.
    function save() {
        if (NotepadStore.currentTab?.isTemporary)
            openPrompt("save");
        else
            flush();
    }

    function openPrompt(kind) {
        const title = NotepadStore.currentTab?.title ?? "Untitled";
        pathPrompt = kind;
        promptInput.text = kind === "save" ? "~/Documents/" + (title.includes(".") ? title : title + ".txt") : "~/";
        promptInput.cursorPosition = promptInput.text.length;
        promptInput.forceActiveFocus();
        errorText = "";
        confirmOverwritePath = "";
    }

    function closePrompt() {
        if (pathPrompt === "")
            return;
        pathPrompt = "";
        confirmOverwritePath = "";
        editor.forceActiveFocus();
    }

    function submitPrompt(text) {
        const trimmed = text.trim();
        if (trimmed === "" || trimmed.endsWith("/"))
            return;
        const path = NotepadStore.resolvePath(trimmed);
        if (pathPrompt === "open") {
            flush();
            rememberPosition();
            NotepadStore.openFile(path);
            closePrompt();
        } else {
            saveAs(path);
        }
    }

    // Checks the target doesn't exist (or that you pressed Enter twice) first.
    function saveAs(path) {
        if (path === confirmOverwritePath) {
            writeTo(path);
            return;
        }
        const probe = probeComponent.createObject(root);
        probe.loaded.connect(() => {
            probe.destroy();
            root.confirmOverwritePath = path;
            root.errorText = "File exists. Press Enter again to replace it.";
        });
        probe.loadFailed.connect(error => {
            probe.destroy();
            if (error === FileViewError.FileNotFound)
                root.writeTo(path);
            else
                root.errorText = "Can't save to " + path;
        });
        probe.path = path;
    }

    function writeTo(path) {
        const index = NotepadStore.currentIndex;
        const text = editor.text;
        const writer = writerComponent.createObject(root);
        writer.saved.connect(() => {
            writer.destroy();
            root.savedText = text;
            root.errorText = "";
            NotepadStore.saveTabAs(index, path);
            root.closePrompt();
        });
        writer.saveFailed.connect(() => {
            writer.destroy();
            root.errorText = "Couldn't write " + path;
        });
        writer.path = path;
        writer.setText(text);
    }

    IpcHandler {
        target: "notepad"

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

    // The current tab's file. Switching tabs changes the path, which loads it.
    FileView {
        id: contentFile
        path: NotepadStore.ready ? NotepadStore.currentPath : ""
        blockWrites: true
        atomicWrites: true
        printErrors: false

        onLoaded: {
            const t = text();
            if (t !== editor.text)
                root.loadText(t);
            else
                root.savedText = t;
        }
        onLoadFailed: error => {
            root.loadText("");
            if (error !== FileViewError.FileNotFound)
                root.errorText = "Couldn't read " + path;
        }
        onSaved: root.errorText = ""
        onSaveFailed: root.errorText = "Couldn't write " + path
    }

    Component {
        id: probeComponent
        FileView {
            printErrors: false
        }
    }

    Component {
        id: writerComponent
        FileView {
            preload: false
            blockWrites: true
            atomicWrites: true
            printErrors: false
        }
    }

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: root.flush()
    }

    PanelWindow {
        id: window

        visible: root.mapped
        anchors {
            top: true
            bottom: true
            right: true
        }
        margins {
            top: Config.notepadEdgeGap
            bottom: Config.notepadEdgeGap
            right: Config.notepadEdgeGap
        }
        implicitWidth: Math.min(root.expanded ? Config.notepadExpandedWidth : Config.notepadWidth, (screen?.width ?? 10000) - Config.notepadEdgeGap * 2)
        // Float over windows instead of pushing them aside.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"

        WlrLayershell.namespace: "qstest:notepad"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible)
                applyBlur();
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
            if (window.BackgroundEffect !== undefined)
                window.BackgroundEffect.blurRegion = Config.blur ? blurRegion : null;
        }

        Shortcut {
            sequences: ["Escape"]
            enabled: root.shown
            onActivated: {
                if (root.renamingIndex >= 0) {
                    root.renamingIndex = -1;
                    editor.forceActiveFocus();
                } else if (root.pathPrompt !== "") {
                    root.closePrompt();
                } else {
                    root.hide();
                }
            }
        }
        Shortcut {
            sequences: [StandardKey.Save]
            enabled: root.shown
            onActivated: root.save()
        }
        Shortcut {
            sequences: [StandardKey.Open]
            enabled: root.shown
            onActivated: root.openPrompt("open")
        }
        Shortcut {
            sequences: ["Ctrl+N", "Ctrl+T"]
            enabled: root.shown
            onActivated: root.newTab()
        }
        Shortcut {
            sequences: ["Ctrl+W"]
            enabled: root.shown
            onActivated: root.closeTab(NotepadStore.currentIndex)
        }
        Shortcut {
            sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
            enabled: root.shown
            onActivated: root.cycleTab(1)
        }
        Shortcut {
            sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab", "Ctrl+PgUp"]
            enabled: root.shown
            onActivated: root.cycleTab(-1)
        }

        Rectangle {
            id: panel

            width: parent.width
            height: parent.height
            x: root.shown ? 0 : width + Config.notepadEdgeGap
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder

            Behavior on x {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                    onRunningChanged: {
                        if (!running && !root.shown)
                            root.mapped = false;
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Theme.spacingXS

                    StyledText {
                        Layout.fillWidth: true
                        text: "Notepad"
                        font.pixelSize: Theme.fontSizeLarge
                    }

                    IconButton {
                        icon: root.expanded ? "unfold_less" : "unfold_more"
                        iconRotation: 90
                        onClicked: root.expanded = !root.expanded
                    }

                    IconButton {
                        icon: "close"
                        onClicked: root.hide()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 40
                    spacing: Theme.spacingS

                    ListView {
                        id: tabList

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        orientation: ListView.Horizontal
                        spacing: Theme.spacingXS
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: NotepadStore.tabs
                        currentIndex: NotepadStore.currentIndex

                        delegate: Rectangle {
                            id: tabItem

                            required property var modelData
                            required property int index
                            readonly property bool current: index === NotepadStore.currentIndex
                            readonly property bool renaming: root.renamingIndex === index

                            width: Math.max(96, Math.min(240, (tabList.width - tabList.spacing * (tabList.count - 1)) / Math.max(1, tabList.count)))
                            height: tabList.height
                            radius: Theme.cornerRadius
                            color: current ? Theme.withAlpha(Theme.surfaceContainerHighest, 0.9) : (tabMouse.containsMouse ? Theme.widgetHover : "transparent")

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton)
                                        root.closeTab(tabItem.index);
                                    else
                                        root.switchTab(tabItem.index);
                                }
                                onDoubleClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton && tabItem.modelData.isTemporary)
                                        root.renamingIndex = tabItem.index;
                                }
                            }

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: closeTabButton.visible ? closeTabButton.left : parent.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: closeTabButton.visible ? Theme.spacingXS : Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !tabItem.renaming
                                text: tabItem.modelData.title
                                color: tabItem.current ? Theme.surfaceText : Theme.surfaceVariantText
                                elide: Text.ElideRight
                            }

                            TextInput {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                visible: tabItem.renaming
                                color: Theme.surfaceText
                                selectionColor: Theme.primarySelected
                                selectedTextColor: Theme.surfaceText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true

                                onVisibleChanged: {
                                    if (visible) {
                                        text = tabItem.modelData.title;
                                        selectAll();
                                        forceActiveFocus();
                                    }
                                }
                                onAccepted: root.finishRename(tabItem.index, text)
                                onActiveFocusChanged: {
                                    if (!activeFocus && tabItem.renaming)
                                        root.finishRename(tabItem.index, text);
                                }
                            }

                            IconButton {
                                id: closeTabButton
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                implicitHeight: 28
                                iconSize: 16
                                icon: "close"
                                contentColor: Theme.surfaceVariantText
                                visible: !tabItem.renaming && (tabItem.current || tabMouse.containsMouse || hovered)
                                onClicked: root.closeTab(tabItem.index)
                            }
                        }
                    }

                    IconButton {
                        icon: "add"
                        onClicked: root.newTab()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surface, 0.5)

                    Flickable {
                        id: flick

                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        contentWidth: width
                        contentHeight: editor.height
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        function ensureVisible(r) {
                            if (contentY >= r.y)
                                contentY = r.y;
                            else if (contentY + height <= r.y + r.height)
                                contentY = r.y + r.height - height;
                        }

                        TextEdit {
                            id: editor

                            width: flick.width
                            // Fill the box so a click anywhere below the text lands in it.
                            height: Math.max(contentHeight, flick.height)
                            color: Theme.surfaceText
                            selectionColor: Theme.primarySelected
                            selectedTextColor: Theme.surfaceText
                            font.family: Config.notepadMonospace ? "monospace" : Theme.fontFamily
                            font.pixelSize: Config.notepadFontSize
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            persistentSelection: true
                            textFormat: TextEdit.PlainText

                            onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                            onTextChanged: {
                                if (!root.loadingText)
                                    saveTimer.restart();
                            }
                        }
                    }

                    StyledText {
                        anchors.left: flick.left
                        anchors.top: flick.top
                        visible: editor.text === ""
                        text: "Start typing…"
                        color: Theme.withAlpha(Theme.surfaceText, 0.4)
                        font.pixelSize: Config.notepadFontSize
                    }

                    // Scroll position, only when the text doesn't fit.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        y: flick.y + flick.visibleArea.yPosition * flick.height
                        width: 4
                        height: flick.visibleArea.heightRatio * flick.height
                        radius: 2
                        color: Theme.withAlpha(Theme.surfaceText, 0.3)
                        visible: flick.contentHeight > flick.height
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    visible: root.pathPrompt !== ""
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.9)

                    MaterialIcon {
                        id: promptIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.pathPrompt === "open" ? "folder_open" : "save"
                        size: 20
                        color: Theme.surfaceVariantText
                    }

                    TextInput {
                        id: promptInput
                        anchors.left: promptIcon.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.surfaceText
                        selectionColor: Theme.primarySelected
                        selectedTextColor: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true

                        onAccepted: root.submitPrompt(text)
                        onTextChanged: root.confirmOverwritePath = ""
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Theme.spacingS

                    IconButton {
                        icon: "save"
                        text: "Save"
                        onClicked: root.save()
                    }

                    IconButton {
                        icon: "folder_open"
                        text: "Open"
                        onClicked: root.openPrompt("open")
                    }

                    IconButton {
                        icon: "note_add"
                        text: "New"
                        onClicked: root.newTab()
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Theme.spacingL

                    StyledText {
                        text: editor.length + " characters"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        text: "Lines: " + editor.text.split("\n").length
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.errorText !== "" ? root.errorText : (root.dirty ? "Saving…" : "Auto saved")
                        color: root.errorText !== "" ? Theme.error : (root.dirty ? Theme.surfaceVariantText : Theme.primary)
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
