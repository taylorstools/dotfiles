import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Notification pop-ups, stacked in the bottom-right corner above the bar
// (bottom right) on the screen niri has focused. Hovering a
// pop-up pauses its timer. Pop-ups that time out stay in the tray.
PanelWindow {
    id: root

    readonly property var shownPopups: Notifications.popups.slice(-Config.notificationMaxPopups)

    screen: {
        const screens = Array.from(Quickshell.screens);
        return screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
    }
    visible: shownPopups.length > 0 || lingering.running
    anchors {
        bottom: true
        right: true
    }
    margins {
        bottom: Theme.spacingS
        right: Theme.spacingS
    }
    implicitWidth: Config.notificationPopupWidth
    implicitHeight: Math.max(1, stack.contentHeight)
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "qstest:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Compositor blur behind the cards (needs a recent Quickshell). The cards
    // share this window, so each adds a region of its own to this one.
    property var cardRegions: []

    Item {
        Region {
            id: blurRegion
        }
    }

    function setCardBlur(region, on) {
        const list = cardRegions.filter(r => r !== region);
        if (on)
            list.push(region);
        cardRegions = list;
        blurRegion.regions = list;
    }

    function applyBlur() {
        if (root.BackgroundEffect !== undefined)
            root.BackgroundEffect.blurRegion = Settings.blur ? blurRegion : null;
    }

    Component.onCompleted: applyBlur()
    onVisibleChanged: applyBlur()

    // Re-apply when blur is switched in the settings window.
    Connections {
        target: Settings
        function onBlurChanged() {
            root.applyBlur();
        }
    }

    // Cards slide in from the right and fade out; the speed is the global
    // animation duration from Settings > Appearance.
    ListView {
        id: stack

        width: parent.width
        height: contentHeight
        spacing: Theme.spacingS
        interactive: false
        // ScriptModel keeps existing delegates (and their timers) when a new
        // pop-up arrives, instead of rebuilding all of them.
        model: ScriptModel {
            values: root.shownPopups
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.animDuration
            }
            NumberAnimation {
                property: "x"
                from: 40
                to: 0
                duration: Theme.animDuration
                easing.type: Easing.OutCubic
            }
        }
        remove: Transition {
            NumberAnimation {
                property: "opacity"
                to: 0
                duration: Theme.animDuration
            }
        }
        displaced: Transition {
            NumberAnimation {
                property: "y"
                duration: Theme.animDuration
                easing.type: Easing.OutCubic
            }
        }

        delegate: NotificationCard {
            id: card

            required property var modelData

            notification: modelData
            popup: true
            width: ListView.view.width

            // Follows the card as it slides in and as the stack moves.
            Region {
                id: cardBlur
                x: card.x
                y: card.y
                width: card.width
                height: card.height
            }

            Component.onCompleted: {
                // Region.radius only exists in newer Quickshell builds.
                if ("radius" in cardBlur)
                    cardBlur.radius = card.radius;
                root.setCardBlur(cardBlur, true);
            }
            Component.onDestruction: root.setCardBlur(cardBlur, false)

            Timer {
                interval: Notifications.popupTimeout(card.modelData)
                running: interval > 0 && !card.hovered
                onTriggered: {
                    // Transient notifications aren't kept in the tray.
                    if (card.modelData.transient)
                        card.modelData.expire();
                    Notifications.hidePopup(card.modelData);
                }
            }
        }
    }

    // After the last pop-up goes, stay up long enough for it to fade out.
    Timer {
        id: lingering
        interval: Theme.animDuration
    }

    onShownPopupsChanged: {
        if (shownPopups.length === 0)
            lingering.restart();
    }
}
