import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The polkit authentication agent: the password prompt behind pkexec, GUI
// "unlock to change this" buttons and the like. Without some agent those
// requests fail silently. Only one agent can register per session, so while
// another runs this one stays unregistered.
Scope {
    id: root

    readonly property var flow: agent.flow
    readonly property bool shown: agent.isActive && flow !== null

    function submit() {
        if (flow && flow.isResponseRequired)
            flow.submit(password.text);
    }

    function cancel() {
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    PolkitAgent {
        id: agent
    }

    PanelMotion {
        id: motion
        shown: root.shown
    }

    PanelWindow {
        id: window

        screen: {
            const screens = Array.from(Quickshell.screens);
            return screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
        }
        visible: motion.mapped
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        // Dims the screen so the prompt reads as a system dialog.
        color: Theme.withAlpha("#000000", 0.35 * motion.progress)

        WlrLayershell.namespace: "qstest:polkit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                password.text = "";
                password.forceActiveFocus();
            }
        }

        // A new request (or a retry after a wrong password) starts empty.
        Connections {
            target: root.flow
            function onIsResponseRequiredChanged() {
                if (root.flow.isResponseRequired) {
                    password.text = "";
                    password.forceActiveFocus();
                }
            }
        }

        Rectangle {
            id: panel

            anchors.centerIn: parent
            width: 420
            height: content.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.blurBorder
            opacity: motion.progress
            scale: 0.95 + 0.05 * motion.progress

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingM

                    MaterialIcon {
                        name: "lock"
                        size: 28
                        filled: true
                        color: Theme.primary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Authentication required"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.flow?.message ?? ""
                    color: Theme.surfaceVariantText
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        const who = root.flow?.selectedIdentity;
                        return who ? "As " + (who.displayName || who.toString()) : "";
                    }
                    color: Theme.outline
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Theme.cornerRadius / 1.5
                    color: Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: password.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.5)

                    TextInput {
                        id: password
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        color: Theme.surfaceText
                        selectionColor: Theme.primarySelected
                        font.family: Theme.fontFamily
                        font.weight: Theme.fontWeight
                        font.pixelSize: 14
                        clip: true
                        enabled: root.flow?.isResponseRequired ?? false
                        onAccepted: root.submit()

                        Keys.onEscapePressed: root.cancel()

                        StyledText {
                            anchors.fill: parent
                            visible: password.text === ""
                            // polkit's own prompt, usually "Password: ".
                            text: (root.flow?.inputPrompt || "Password").replace(/:\s*$/, "")
                            color: Theme.withAlpha(Theme.surfaceText, 0.4)
                            font.pixelSize: 14
                        }
                    }
                }

                // Wrong password and other messages from polkit.
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.flow?.supplementaryMessage ?? ""
                    color: root.flow?.supplementaryIsError ? Theme.error : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    Item {
                        Layout.fillWidth: true
                    }

                    IconButton {
                        implicitHeight: 34
                        text: "Cancel"
                        restColor: Theme.surfaceContainerHigh
                        onClicked: root.cancel()
                    }

                    Rectangle {
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: authText.implicitWidth + Theme.spacingL * 2
                        radius: Theme.cornerRadius / 2
                        color: authMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.85) : Theme.primary

                        StyledText {
                            id: authText
                            anchors.centerIn: parent
                            text: "Authenticate"
                            color: Theme.onPrimary
                        }

                        MouseArea {
                            id: authMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
}
