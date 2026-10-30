import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// The flyout behind the bar's wifi / bluetooth / volume icons: who's logged
// in, settings / lock / power, brightness and volume with an output picker,
// and a Wi-Fi / Bluetooth list. Click the icons, or
//   qs ipc -p <this folder> call controlcenter toggle
// Esc or a click outside closes it.
Scope {
    id: root

    readonly property bool shown: Popouts.controlCenterScreen !== null
    property string tab: "wifi"
    property bool powerMenuOpen: false
    property bool outputsOpen: false
    // The secured network whose password field is showing, and what's typed
    // in it. Kept here because the network list is rebuilt whenever
    // NetworkManager reports a change, which would wipe the field.
    property string passwordSsid: ""
    // The menu for one network (right-click it, or the gear on the connected
    // one): { ssid, active, saved, x, y } in panel coordinates, or null.
    property var netMenu: null
    property string passwordDraft: ""
    property bool showPassword: false

    readonly property string userName: {
        const name = Quickshell.env("USER") || "";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

    readonly property var btAdapter: Bluetooth.defaultAdapter
    // Named devices only, connected first, then paired, then by name.
    readonly property var btDevices: {
        const devices = (Bluetooth.devices ? Bluetooth.devices.values : []).filter(d => d.name && d.name.replace(/-/g, ":") !== d.address);
        return devices.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
    }

    function close() {
        Popouts.controlCenterScreen = null;
    }

    // Only networks it has something to offer for: Disconnect when
    // connected, Forget when saved.
    function openNetMenu(net, item, x, y) {
        if (!net.active && !net.saved)
            return;
        const p = item.mapToItem(panel, x, y);
        netMenu = {
            "ssid": net.ssid,
            "active": net.active,
            "saved": net.saved,
            "x": p.x,
            "y": p.y
        };
    }

    // Opens a network's password field, empty and hidden.
    function askPassword(ssid) {
        passwordDraft = "";
        showPassword = false;
        passwordSsid = ssid;
    }

    function nodeName(node) {
        return node ? (node.nickname || node.description || node.name) : "";
    }

    function btIcon(device) {
        const icon = device.icon || "";
        if (icon.includes("headset") || icon.includes("headphone"))
            return "headphones";
        if (icon.startsWith("audio"))
            return "speaker";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("keyboard"))
            return "keyboard";
        if (icon.includes("gaming"))
            return "sports_esports";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("computer"))
            return "computer";
        return "bluetooth";
    }

    function btStatus(device) {
        if (device.state === BluetoothDeviceState.Connecting)
            return "Connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting…";
        if (device.pairing)
            return "Pairing…";
        // Connected devices show a Disconnect button instead; only the
        // battery level is left to say.
        if (device.connected)
            return device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
        return device.paired ? "Paired" : "";
    }

    // Connecting or pairing; disconnecting has its own button.
    function activateDevice(device) {
        if (device.connected)
            return;
        if (device.paired)
            device.connect();
        else
            device.pair();
    }

    // Scan only while the Bluetooth list is on screen.
    function updateDiscovery() {
        if (btAdapter && btAdapter.enabled)
            btAdapter.discovering = shown && tab === "bluetooth";
    }

    onShownChanged: {
        if (shown) {
            window.screen = Popouts.controlCenterScreen;
            Brightness.refresh();
            Network.listNetworks = true;
            Network.scan();
        } else {
            powerMenuOpen = false;
            netMenu = null;
            outputsOpen = false;
            passwordSsid = "";
            passwordDraft = "";
            Network.listNetworks = false;
            Network.lastError = "";
        }
        updateDiscovery();
    }
    onTabChanged: updateDiscovery()

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            if (root.shown) {
                root.close();
                return;
            }
            const screens = Array.from(Quickshell.screens);
            Popouts.controlCenterScreen = screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        function close(): void {
            root.close();
        }
    }

    PwObjectTracker {
        objects: root.sinks
    }

    // A saved network failed to connect: ask for its password in its row.
    Connections {
        target: Network
        function onPasswordNeededChanged() {
            if (Network.passwordNeeded !== "" && root.shown)
                root.askPassword(Network.passwordNeeded);
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

        WlrLayershell.namespace: "qstest:controlcenter"
        WlrLayershell.layer: WlrLayer.Top
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
            onActivated: {
                if (root.netMenu !== null)
                    root.netMenu = null;
                else if (root.passwordSsid !== "")
                    root.passwordSsid = "";
                else if (root.powerMenuOpen)
                    root.powerMenuOpen = false;
                else
                    root.close();
            }
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

            readonly property real pad: 14

            // Attached: reaches Theme.flyoutOvershoot past the taskbar and the
            // screen edge, so only the top-left corner is rounded and only the
            // top and left borders show. The content keeps clear of that strip.
            readonly property real overshoot: Theme.flyoutOvershoot

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.attachPanels ? -overshoot : Theme.spacingS
            width: Config.controlCenterWidth + overshoot
            height: content.implicitHeight + pad * 2 + overshoot
            radius: Theme.flyoutRadius
            color: Theme.popupBackground
            border.width: Theme.edgePanelBorder ? 1 : 0
            border.color: Theme.blurBorder

            // Swallows clicks so they don't close the panel; closes the power menu.
            MouseArea {
                anchors.fill: parent
                onClicked: root.powerMenuOpen = false
            }

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: panel.pad
                anchors.rightMargin: panel.pad + panel.overshoot
                anchors.bottomMargin: panel.pad + panel.overshoot
                spacing: 14

                RowLayout {
                    id: header

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 6

                    ClippingRectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 17
                        color: Theme.surfaceContainerHighest
                        border.width: 1
                        border.color: Theme.primary

                        // AccountsService first (what greeters use), then ~/.face.
                        Image {
                            id: avatar

                            property int candidate: 0
                            readonly property var candidates: ["/var/lib/AccountsService/icons/" + Quickshell.env("USER"), Quickshell.env("HOME") + "/.face"]

                            anchors.fill: parent
                            source: candidate < candidates.length ? "file://" + candidates[candidate] : ""
                            sourceSize.width: 68
                            sourceSize.height: 68
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: {
                                if (status === Image.Error)
                                    candidate++;
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: avatar.status !== Image.Ready
                            text: root.userName.charAt(0)
                            color: Theme.primary
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        text: root.userName
                        font.pixelSize: Theme.fontSizeLarge
                        elide: Text.ElideRight
                    }

                    IconButton {
                        implicitHeight: 34
                        icon: "settings"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: {
                            root.close();
                            Popouts.settingsOpen = true;
                        }
                    }

                    IconButton {
                        implicitHeight: 34
                        icon: "lock"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: {
                            root.close();
                            Power.lock();
                        }
                    }

                    IconButton {
                        id: powerButton
                        implicitHeight: 34
                        icon: "power_settings_new"
                        restColor: root.powerMenuOpen ? Theme.withAlpha(Theme.primary, 0.25) : Theme.surfaceContainerHigh
                        onClicked: root.powerMenuOpen = !root.powerMenuOpen
                    }
                }

                // Brightness, volume and the output picker.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: levels.implicitHeight + 24
                    radius: 10
                    color: Theme.surfaceContainerHigh

                    ColumnLayout {
                        id: levels

                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // The 8px insets line the sun, speaker and Audio Output
                        // icons up with the Wi-Fi and Bluetooth list icons below.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            visible: Brightness.available
                            spacing: 10

                            MaterialIcon {
                                name: "light_mode"
                                size: 20
                                color: Theme.surfaceVariantText
                            }

                            StyledSlider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                value: Brightness.value
                                onMoved: v => Brightness.set(v)
                            }

                            StyledText {
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(brightnessSlider.shownValue * 100) + "%"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            spacing: 10

                            // Click the speaker icon to mute.
                            MaterialIcon {
                                name: !root.audio || root.audio.muted ? "volume_off" : (root.audio.volume <= 0.33 ? "volume_down" : "volume_up")
                                size: 20
                                color: Theme.surfaceVariantText

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.audio)
                                            root.audio.muted = !root.audio.muted;
                                    }
                                }
                            }

                            StyledSlider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                value: root.audio ? root.audio.volume : 0
                                opacity: root.audio && root.audio.muted ? 0.5 : 1
                                onMoved: v => {
                                    if (!root.audio)
                                        return;
                                    root.audio.volume = v;
                                    if (v > 0)
                                        root.audio.muted = false;
                                }
                            }

                            StyledText {
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(volumeSlider.shownValue * 100) + "%"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            radius: 8
                            color: outputMouse.containsMouse ? Theme.widgetHover : Theme.surfaceContainerHighest

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                MaterialIcon {
                                    name: "speaker"
                                    size: 20
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: "Audio Output"
                                    font.pixelSize: 13
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: root.nodeName(root.sink)
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }

                                MaterialIcon {
                                    name: root.outputsOpen ? "expand_less" : "expand_more"
                                    size: 18
                                    color: Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                id: outputMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.outputsOpen = !root.outputsOpen
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.outputsOpen
                            spacing: 2

                            Repeater {
                                model: root.sinks

                                delegate: Rectangle {
                                    id: outputItem

                                    required property var modelData
                                    readonly property bool current: modelData === root.sink

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    radius: 8
                                    color: current ? Theme.withAlpha(Theme.primary, 0.18) : (itemMouse.containsMouse ? Theme.widgetHover : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        MaterialIcon {
                                            name: outputItem.current ? "check" : ""
                                            size: 18
                                            color: Theme.primary
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.nodeName(outputItem.modelData)
                                            color: outputItem.current ? Theme.primary : Theme.surfaceText
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Pipewire.preferredDefaultAudioSink = outputItem.modelData;
                                            root.outputsOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Wi-Fi / Bluetooth.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: connections.implicitHeight + 20
                    radius: 10
                    color: Theme.surfaceContainerHigh

                    ColumnLayout {
                        id: connections

                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 10
                            color: Theme.surfaceContainer

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 3
                                spacing: 6

                                SegmentButton {
                                    icon: "wifi"
                                    text: "Wi-Fi"
                                    current: root.tab === "wifi"
                                    onClicked: root.tab = "wifi"
                                }
                                SegmentButton {
                                    icon: "bluetooth"
                                    text: "Bluetooth"
                                    current: root.tab === "bluetooth"
                                    onClicked: root.tab = "bluetooth"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Layout.bottomMargin: 4
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                text: root.tab === "wifi" ? "Networks" : "Devices"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            IconButton {
                                id: refreshButton

                                readonly property bool busy: root.tab === "wifi" ? Network.scanning : (root.btAdapter?.discovering ?? false)

                                implicitHeight: 26
                                icon: "refresh"
                                iconSize: 18
                                contentColor: Theme.surfaceVariantText
                                visible: root.tab === "wifi"
                                onClicked: Network.scan()

                                RotationAnimator on rotation {
                                    running: refreshButton.busy && refreshButton.visible
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    onRunningChanged: {
                                        if (!running)
                                            refreshButton.rotation = 0;
                                    }
                                }
                            }

                            Toggle {
                                checked: root.tab === "wifi" ? Network.wifiEnabled : (root.btAdapter?.enabled ?? false)
                                onToggled: {
                                    if (root.tab === "wifi") {
                                        Network.setWifiEnabled(!Network.wifiEnabled);
                                    } else if (root.btAdapter) {
                                        root.btAdapter.enabled = !root.btAdapter.enabled;
                                        Qt.callLater(root.updateDiscovery);
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.bottomMargin: 4
                            visible: root.tab === "wifi" && Network.lastError !== ""
                            text: Network.lastError
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                        }

                        Item {
                            Layout.fillWidth: true
                            // Whole rows (38px + 2px spacing), so at rest the
                            // last one isn't cut in half: with an attached panel
                            // that looks like the taskbar cutting the list off.
                            Layout.preferredHeight: Config.controlCenterListRows * 40 - 2

                            ListView {
                                id: wifiList
                                anchors.fill: parent
                                visible: root.tab === "wifi"
                                clip: true
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                model: Network.wifiEnabled ? Network.networks : []

                                delegate: Rectangle {
                                    id: netItem

                                    required property var modelData
                                    readonly property bool asking: root.passwordSsid === modelData.ssid
                                    readonly property bool connecting: Network.connectingSsid === modelData.ssid

                                    function submit() {
                                        if (passwordInput.text === "")
                                            return;
                                        Network.connect(modelData.ssid, passwordInput.text);
                                        root.passwordSsid = "";
                                    }

                                    // Fill in the draft: empty for a new prompt
                                    // (root.askPassword cleared it), or what was
                                    // typed if the list was rebuilt meanwhile.
                                    function restoreDraft() {
                                        if (!asking)
                                            return;
                                        passwordInput.text = root.passwordDraft;
                                        passwordInput.forceActiveFocus();
                                    }

                                    onAskingChanged: restoreDraft()
                                    Component.onCompleted: restoreDraft()

                                    width: ListView.view.width
                                    height: asking ? 80 : 38
                                    radius: 8
                                    color: modelData.active ? Theme.withAlpha(Theme.primary, 0.18) : (netMouse.containsMouse ? Theme.widgetHover : "transparent")

                                    RowLayout {
                                        x: 10
                                        width: parent.width - 20
                                        height: 38
                                        spacing: 10

                                        MaterialIcon {
                                            name: Network.signalIcon(netItem.modelData.signal)
                                            size: 20
                                            filled: netItem.modelData.active
                                            color: netItem.modelData.active ? Theme.primary : Theme.surfaceText
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: netItem.modelData.ssid
                                            color: netItem.modelData.active ? Theme.primary : Theme.surfaceText
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            visible: text !== ""
                                            text: netItem.connecting ? "Connecting…" : ""
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        // Disconnecting takes this button, so a
                                        // stray click on the row can't do it.
                                        TextButton {
                                            visible: netItem.modelData.active
                                            text: "Disconnect"
                                            onClicked: Network.disconnect()
                                        }

                                        // Where the other rows have the lock: the
                                        // same menu as a right-click. The negative
                                        // margin lines its icon up with the locks.
                                        IconButton {
                                            id: netGear
                                            visible: netItem.modelData.active
                                            Layout.rightMargin: -5
                                            implicitHeight: 26
                                            icon: "settings"
                                            iconSize: 16
                                            contentColor: Theme.surfaceVariantText
                                            onClicked: root.openNetMenu(netItem.modelData, netGear, netGear.width - 170, netGear.height + 4)
                                        }

                                        MaterialIcon {
                                            visible: netItem.modelData.secure && !netItem.modelData.active
                                            name: "lock"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                        }
                                    }

                                    // Under the row's buttons (z -1), so Disconnect
                                    // and the gear get their own clicks. A left
                                    // click on the connected row does nothing;
                                    // right-click opens the network menu.
                                    MouseArea {
                                        id: netMouse
                                        z: -1
                                        width: parent.width
                                        height: 38
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: netItem.modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            const net = netItem.modelData;
                                            if (mouse.button === Qt.RightButton) {
                                                root.openNetMenu(net, netMouse, mouse.x, mouse.y);
                                            } else if (net.active) {
                                                return;
                                            } else if (net.secure && !net.saved) {
                                                root.askPassword(net.ssid);
                                            } else {
                                                root.passwordSsid = "";
                                                Network.connect(net.ssid, "");
                                            }
                                        }
                                    }

                                    // Password field with a show/hide eye, and Connect.
                                    RowLayout {
                                        x: 10
                                        y: 40
                                        width: parent.width - 20
                                        height: 32
                                        visible: netItem.asking
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 6
                                            color: Theme.surfaceContainer
                                            border.width: 1
                                            border.color: passwordInput.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)

                                            TextInput {
                                                id: passwordInput
                                                anchors.left: parent.left
                                                anchors.right: eyeButton.left
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                                color: Theme.surfaceText
                                                selectionColor: Theme.primarySelected
                                                font.family: Theme.fontFamily
                                                font.weight: Theme.fontWeight
                                                font.pixelSize: 13
                                                clip: true
                                                onAccepted: netItem.submit()
                                                onTextChanged: {
                                                    if (netItem.asking)
                                                        root.passwordDraft = text;
                                                }

                                                StyledText {
                                                    anchors.fill: parent
                                                    visible: passwordInput.text === ""
                                                    text: netItem.modelData.saved ? "New password" : "Password"
                                                    color: Theme.withAlpha(Theme.surfaceText, 0.4)
                                                    font.pixelSize: 13
                                                }
                                            }

                                            IconButton {
                                                id: eyeButton
                                                anchors.right: parent.right
                                                anchors.rightMargin: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                implicitHeight: 28
                                                icon: root.showPassword ? "visibility_off" : "visibility"
                                                iconSize: 17
                                                contentColor: Theme.surfaceVariantText
                                                onClicked: {
                                                    root.showPassword = !root.showPassword;
                                                    passwordInput.forceActiveFocus();
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: connectText.implicitWidth + 24
                                            radius: 6
                                            color: passwordInput.text === "" ? Theme.surfaceContainerHighest : (connectMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.85) : Theme.primary)

                                            StyledText {
                                                id: connectText
                                                anchors.centerIn: parent
                                                text: "Connect"
                                                color: passwordInput.text === "" ? Theme.outline : Theme.onPrimary
                                                font.pixelSize: 13
                                            }

                                            MouseArea {
                                                id: connectMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: netItem.submit()
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: wifiList.count === 0
                                    text: !Network.wifiEnabled ? "Wi-Fi is off" : (Network.scanning ? "Scanning…" : "No networks found")
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: 13
                                }
                            }

                            ListView {
                                id: btList
                                anchors.fill: parent
                                visible: root.tab === "bluetooth"
                                clip: true
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.btAdapter?.enabled ? root.btDevices : []

                                delegate: Rectangle {
                                    id: btItem

                                    required property var modelData

                                    width: ListView.view.width
                                    height: 38
                                    radius: 8
                                    color: modelData.connected ? Theme.withAlpha(Theme.primary, 0.18) : (btMouse.containsMouse ? Theme.widgetHover : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        MaterialIcon {
                                            name: root.btIcon(btItem.modelData)
                                            size: 20
                                            filled: btItem.modelData.connected
                                            color: btItem.modelData.connected ? Theme.primary : Theme.surfaceText
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: btItem.modelData.name
                                            color: btItem.modelData.connected ? Theme.primary : Theme.surfaceText
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            visible: text !== ""
                                            text: root.btStatus(btItem.modelData)
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }

                                        TextButton {
                                            visible: btItem.modelData.connected && btItem.modelData.state !== BluetoothDeviceState.Disconnecting
                                            text: "Disconnect"
                                            onClicked: btItem.modelData.disconnect()
                                        }
                                    }

                                    // Off on a connected device, so it doesn't
                                    // cover the Disconnect button.
                                    MouseArea {
                                        id: btMouse
                                        anchors.fill: parent
                                        z: -1
                                        enabled: !btItem.modelData.connected
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activateDevice(btItem.modelData)
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: btList.count === 0
                                    text: !root.btAdapter ? "No Bluetooth adapter" : (!root.btAdapter.enabled ? "Bluetooth is off" : "Looking for devices…")
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }

            // Power menu, dropped down under the power button.
            Rectangle {
                x: panel.width - panel.overshoot - panel.pad - width
                y: panel.pad + header.height + 6
                z: 10
                width: 170
                height: powerItems.implicitHeight + 8
                visible: root.powerMenuOpen
                radius: 10
                // Solid, so it reads over the panel whatever the overlay opacity.
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 1)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)

                Column {
                    id: powerItems
                    anchors.fill: parent
                    anchors.margins: 4

                    PowerItem {
                        icon: "bedtime"
                        text: "Sleep"
                        onClicked: {
                            root.close();
                            Power.sleep();
                        }
                    }
                    PowerItem {
                        icon: "restart_alt"
                        text: "Restart"
                        onClicked: {
                            root.close();
                            Power.restart();
                        }
                    }
                    PowerItem {
                        icon: "power_settings_new"
                        text: "Shut down"
                        contentColor: Theme.error
                        onClicked: {
                            root.close();
                            Power.shutdown();
                        }
                    }
                }
            }

            // Closes the network menu on a click anywhere else in the panel.
            MouseArea {
                anchors.fill: parent
                z: 19
                visible: root.netMenu !== null
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.netMenu = null
            }

            // The network menu, at the pointer or under the gear. Solid, so it
            // reads over the list whatever the overlay opacity.
            Rectangle {
                z: 20
                visible: root.netMenu !== null
                width: 170
                height: netItems.implicitHeight + 8
                x: Math.max(6, Math.min(root.netMenu?.x ?? 0, panel.width - panel.overshoot - width - 6))
                y: Math.max(6, Math.min(root.netMenu?.y ?? 0, panel.height - panel.overshoot - height - 6))
                radius: 10
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 1)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)

                Column {
                    id: netItems
                    anchors.fill: parent
                    anchors.margins: 4

                    PowerItem {
                        visible: root.netMenu?.active ?? false
                        icon: "link_off"
                        text: "Disconnect"
                        onClicked: {
                            root.netMenu = null;
                            Network.disconnect();
                        }
                    }
                    PowerItem {
                        visible: root.netMenu?.saved ?? false
                        icon: "delete"
                        text: "Forget"
                        contentColor: Theme.error
                        onClicked: {
                            const ssid = root.netMenu.ssid;
                            root.netMenu = null;
                            if (root.passwordSsid === ssid)
                                root.passwordSsid = "";
                            Network.forget(ssid);
                        }
                    }
                }
            }
        }
    }

    // A power menu entry.
    component PowerItem: Rectangle {
        id: powerItem

        property string icon
        property string text
        property color contentColor: Theme.surfaceText

        signal clicked

        width: parent.width
        height: 36
        radius: 8
        color: powerMouse.containsMouse ? Theme.widgetHover : "transparent"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: powerItem.icon
                size: 18
                color: powerItem.contentColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: powerItem.text
                color: powerItem.contentColor
                font.pixelSize: 13
            }
        }

        MouseArea {
            id: powerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: powerItem.clicked()
        }
    }
}
