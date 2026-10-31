import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Notification pop-ups, stacked in the bottom-right corner above the bar or
// the top-right corner (Settings > Notifications) on the screen niri has
// focused, newest nearest the corner. Hovering a pop-up pauses its timer.
// Pop-ups that time out stay in the tray.
PanelWindow {
    id: root

    readonly property var shownPopups: Notifications.popups.slice(-Config.notificationMaxPopups)
    readonly property bool atTop: Settings.notificationPosition === "top-right"
    // Twice niri's window gap (layout.kdl), so cards sit inside window edges
    // instead of lining up with them.
    readonly property real inset: Theme.spacingL
    readonly property int slideDuration: Notifications.popupSlideDuration
    // Card plus inset: just off the screen edge. Not root.width, which is
    // still 0 when the first card is made, so it was drawn in place once.
    readonly property real slideDistance: Config.notificationPopupWidth + inset

    screen: {
        const screens = Array.from(Quickshell.screens);
        return screens.find(s => s.name === Niri.focusedOutput) ?? screens[0];
    }
    visible: shownPopups.length > 0
    // Mapping the window takes about as long as the slide, so a card that
    // arrives with it waits for the window's first frame (see the delegate).
    property bool painted: false
    onVisibleChanged: {
        if (!visible)
            painted = false;
        applyBlur();
    }

    Connections {
        target: stack.Window.window
        function onFrameSwapped() {
            if (root.visible)
                root.painted = true;
        }
    }
    // The whole height of the screen's right edge, so a card sliding out
    // isn't clipped when the stack shrinks. The right inset is inside the
    // window, so cards slide across it from the screen edge.
    anchors {
        top: true
        bottom: true
        right: true
    }
    margins {
        top: root.inset
        bottom: root.inset
    }
    implicitWidth: Config.notificationPopupWidth + inset
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.namespace: "qstest:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the stacked cards take clicks; the rest goes to the windows below.
    mask: Region {
        x: 0
        y: root.atTop ? 0 : stack.height - stack.contentHeight
        width: stack.width
        height: stack.contentHeight
    }

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

    // Re-apply when blur is switched in the settings window.
    Connections {
        target: Settings
        function onBlurChanged() {
            root.applyBlur();
        }
    }

    // The speed follows the global animation duration from Settings > Appearance.
    ListView {
        id: stack

        width: Config.notificationPopupWidth
        height: parent.height
        spacing: Theme.spacingS
        interactive: false
        // Newest first, stacked out from the corner.
        verticalLayoutDirection: root.atTop ? ListView.TopToBottom : ListView.BottomToTop
        // ScriptModel keeps existing delegates (and their timers) when a new
        // pop-up arrives, instead of rebuilding all of them.
        model: ScriptModel {
            values: root.shownPopups.slice().reverse()
        }

        // Cards slide themselves in and out: the list's own add and remove
        // animations don't run for the first and last pop-up. This one is
        // for the oldest pop-up when a new one pushes it past the limit.
        remove: Transition {
            NumberAnimation {
                property: "x"
                to: root.slideDistance
                duration: root.slideDuration
                easing.type: Easing.InCubic
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
            readonly property bool leaving: Notifications.leaving.includes(modelData)

            notification: modelData
            popup: true
            width: ListView.view.width

            onLeavingChanged: {
                if (leaving)
                    slideOut.start();
            }

            // The slide moves this, not x: the list sets x to 0 when it lays
            // the card out, which drew a new card in place for a frame.
            transform: Translate {
                id: slide
                x: root.slideDistance
            }

            NumberAnimation {
                id: slideIn
                target: slide
                property: "x"
                from: root.slideDistance
                to: 0
                duration: root.slideDuration
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: slideOut
                target: slide
                property: "x"
                to: root.slideDistance
                duration: root.slideDuration
                easing.type: Easing.InCubic
            }

            // Follows the card as it slides in and as the stack moves.
            Region {
                id: cardBlur
                // Card positions count from the list's content, which sits
                // lower in the window when the stack starts at the bottom.
                x: stack.contentItem.x + card.x + slide.x
                y: stack.contentItem.y + card.y
                width: card.width
                height: card.height
            }

            property bool slidIn: false

            function startSlideIn() {
                if (slidIn || !root.painted)
                    return;
                slidIn = true;
                slideIn.start();
            }

            Connections {
                target: root
                function onPaintedChanged() {
                    card.startSlideIn();
                }
            }

            Component.onCompleted: {
                startSlideIn();
                // Region.radius only exists in newer Quickshell builds.
                if ("radius" in cardBlur)
                    cardBlur.radius = card.radius;
                root.setCardBlur(cardBlur, true);
            }
            Component.onDestruction: root.setCardBlur(cardBlur, false)

            Timer {
                interval: Notifications.popupTimeout(card.modelData)
                running: interval > 0 && !card.hovered && !card.leaving
                onTriggered: {
                    const n = card.modelData;
                    // Transient notifications aren't kept in the tray.
                    Notifications.closePopup(n, n.transient ? () => n.expire() : null);
                }
            }
        }
    }

}
