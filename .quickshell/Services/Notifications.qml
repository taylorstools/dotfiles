pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Common

// The notification daemon. Every notification is kept (tracked) until you
// dismiss it, so the clock flyout's Notifications tab lists them; new ones
// also go into `popups` for the corner pop-ups unless do not disturb is on.
// Only one program can own the notification D-Bus name, so this only
// receives anything while no other notification daemon runs.
//   qs ipc -p <this folder> call notifications toggleDnd | clearAll
Singleton {
    id: root

    // Newest first. Transient notifications only ever show as pop-ups.
    readonly property var list: server.trackedNotifications.values.filter(n => !n.transient).sort((a, b) => b.id - a.id)
    // Oldest first, so the newest pop-up sits at the bottom, nearest the bar.
    property var popups: []
    readonly property bool dnd: Settings.doNotDisturb
    // Arrival times by notification id; the server doesn't keep them.
    property var _received: ({})
    // Pop-ups slide in from the screen's right edge and back out to it.
    readonly property int popupSlideDuration: Theme.animDuration * 2
    // Pop-ups sliding out; they leave `popups` once they're off screen.
    property var leaving: []
    // What closePopup() runs once its pop-up has slid out.
    property var _afterSlide: []

    function toggleDnd() {
        Settings.doNotDisturb = !Settings.doNotDisturb;
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
    }

    function hidePopup(notification) {
        popups = popups.filter(n => n !== notification);
        leaving = leaving.filter(n => n !== notification);
    }

    // Slides a pop-up out, then takes it off the list and runs `then` (if
    // given). The pop-up slides itself rather than through the list's remove
    // animation, which doesn't run when the last one goes. Dismissing or
    // running an action destroys the notification, so those wait too, or the
    // card would slide out blank.
    function closePopup(notification, then) {
        if (leaving.includes(notification))
            return;
        leaving = leaving.concat([notification]);
        _afterSlide = _afterSlide.concat([
            {
                notification: notification,
                then: then
            }
        ]);
        afterSlide.restart();
    }

    function receivedAt(notification) {
        return (notification && _received[notification.id]) ?? new Date();
    }

    // "now", "5 min ago", "2 hr ago", then the date.
    function ago(notification, now) {
        if (!notification)
            return "";
        const minutes = Math.floor((now - receivedAt(notification)) / 60000);
        if (minutes < 1)
            return "now";
        if (minutes < 60)
            return minutes + " min ago";
        if (minutes < 24 * 60)
            return Math.floor(minutes / 60) + " hr ago";
        return Qt.formatDate(receivedAt(notification), "M/d");
    }

    // How long a pop-up stays: what the app asked for, 5 s if it didn't
    // say, and until dismissed for critical ones. 0 means stay.
    function popupTimeout(notification) {
        if (notification.urgency === NotificationUrgency.Critical)
            return 0;
        return notification.expireTimeout > 0 ? notification.expireTimeout * 1000 : 5000;
    }

    // Clicking a notification runs its "default" action if it has one.
    // A click on the body: the "default" action, else the first one (scripts
    // here rely on that, e.g. the autoupgrade failure's "open the log").
    function activate(notification) {
        const actions = Array.from(notification.actions);
        const action = actions.find(a => a.identifier === "default") ?? actions[0];
        if (action)
            action.invoke();
        else
            notification.dismiss();
    }

    Timer {
        id: afterSlide
        interval: root.popupSlideDuration
        onTriggered: {
            const queued = root._afterSlide;
            root._afterSlide = [];
            for (const entry of queued) {
                root.hidePopup(entry.notification);
                entry.then?.();
            }
        }
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        persistenceSupported: true

        onNotification: notification => {
            notification.tracked = true;
            const received = Object.assign({}, root._received);
            received[notification.id] = new Date();
            root._received = received;
            notification.closed.connect(() => root.hidePopup(notification));
            if (!root.dnd || notification.urgency === NotificationUrgency.Critical)
                root.popups = root.popups.filter(n => n.id !== notification.id).concat([notification]);
        }
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            root.toggleDnd();
        }
        function clearAll(): void {
            root.clearAll();
        }
    }
}
