import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Common
import qs.Services

// The session lock that replaced hyprlock, looking like it (LockSurface.qml).
// Behaves like it too: authentication starts the moment it locks; Enter
// sends the password (an empty one is ignored); a wrong one shows "Try
// again" and starts over.
//   qs ipc call lock lock         lock now
//   qs ipc call lock isLocked     "true" while locked
//   qs ipc call lock isSecure     "true" once niri has confirmed the lock
//   qs ipc call lock preview      the lock screen in a normal overlay that
//                                 locks nothing: a password or face that
//                                 would unlock closes it (Esc also does), so
//                                 PAM can be tried without risk
// scripts/hypridle/lock-session.sh is what everything else calls.
//
// While locked, a marker file stays in $XDG_RUNTIME_DIR. niri keeps the
// session locked if the shell dies, so a restarted shell (or a config
// reload) sees the marker and locks again instead of leaving a blank screen.
Scope {
    id: root

    // Starts locked when a marker was left: a config reload or a restarted
    // shell must not drop the lock even for a moment, and reading the marker
    // any later would (the lock would come up unlocked, then lock again).
    property bool locked: startupMarker.text() !== ""
    readonly property bool secure: sessionLock.secure
    property bool previewing: false
    onPreviewingChanged: {
        if (!previewing && !locked)
            pam.abort();
    }

    // What the screens share: the typed password, and "" / "checking" / "failed".
    property string password: ""
    property string authState: ""
    // authState has been "checking" for a moment (the field's red outline).
    property bool showChecking: false
    onAuthStateChanged: {
        if (authState === "checking") {
            showCheckingDelay.restart();
        } else {
            showCheckingDelay.stop();
            showChecking = false;
        }
    }

    // A right password is checked in a few hundred ms; a wrong one takes
    // about 2 s (pam_unix stalls on failure). So the red only ever shows for
    // a wrong one.
    Timer {
        id: showCheckingDelay
        interval: 1000
        onTriggered: root.showChecking = true
    }
    // Sent once PAM asks: Enter can come before PAM is ready for it.
    property string pendingPassword: ""

    readonly property string userName: {
        const user = Quickshell.env("USER") || "";
        return user.charAt(0).toUpperCase() + user.slice(1);
    }
    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qstest-locked." + (Quickshell.env("WAYLAND_DISPLAY") || "wayland")
    // Reloaded on every lock: the effects script rewrites it per wallpaper.
    property string backgroundSource: ""

    // hyprlock_battery.sh: a battery a tenth full per step, a plug while charging.
    readonly property string batteryText: {
        const percent = Math.round(BatteryInfo.level);
        const icons = ["\u{f0083}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}", "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0079}", "\u{f0079}"];
        const icon = BatteryInfo.charging ? "\uf1e6" : icons[Math.min(10, Math.floor(percent / 10))];
        return icon + "  " + percent + "%";
    }

    function refreshBackground() {
        backgroundSource = "";
        backgroundSource = "file://" + Quickshell.env("HOME") + "/.config/.EffectsWallpaper.png";
    }

    function lock() {
        if (unlocking) {
            // Still locked, waiting for the fade window: stay locked.
            if (locked) {
                unlocking = false;
                startAuth();
                return;
            }
            // Already unlocked and fading out: drop the fade, lock as usual.
            fadeOut.stop();
            unlocking = false;
            fade = 1;
        }
        if (locked || locking)
            return;
        refreshBackground();
        password = "";
        pendingPassword = "";
        authState = "";
        previewing = false;
        // hyprlock fades in over the desktop; niri can't show the desktop
        // under a lock, so a copy fades in first (fadeWindows) and the real
        // lock takes over once it's opaque.
        locking = true;
        fade = 0;
    }

    // The fade starts once the copy is on screen. Its window's first drawn
    // frames don't reach the screen for about 250 ms (measured), as long as
    // the fade itself, so starting on the first frame showed only its end.
    function startFadeIn() {
        if (!locking || locked || fadeIn.running || fadeInDelay.running)
            return;
        fadeInDelay.restart();
    }

    function runFadeIn() {
        if (!locking || locked || fadeIn.running)
            return;
        fadeInDelay.stop();
        fadeIn.restart();
    }

    function engage() {
        markerFile.setText("locked\n");
        locked = true;
        startAuth();
        lockTimeout.restart();
    }

    property bool locking: false
    // The copy goes once niri confirms the lock and draws it on top.
    onSecureChanged: {
        if (secure && locking) {
            locking = false;
            lockTimeout.stop();
        }
    }

    // hyprlock's fade-in, measured from a recording: about 0.3 s, starting
    // gently.
    NumberAnimation {
        id: fadeIn
        target: root
        property: "fade"
        to: 1
        duration: 300
        easing.type: Easing.InOutQuad
        onFinished: root.engage()
    }

    Timer {
        id: fadeInDelay
        interval: 250
        onTriggered: root.runFadeIn()
    }

    // A lock niri never confirms: don't leave the copy over the screen.
    Timer {
        id: lockTimeout
        interval: 3000
        onTriggered: root.locking = false
    }

    // Like hyprlock, the lock fades away over the desktop. niri draws its own
    // red backdrop, not the session, behind a see-through lock, and has no
    // unlock animation, so the fade happens after unlocking: a copy of the
    // lock screen goes up on the overlay layer (fadeWindows), the session is
    // unlocked once that copy has been drawn, then the copy fades out.
    function unlock() {
        pam.abort();
        pendingPassword = "";
        // Accepted: no red, not even fading out (LockSurface snaps it off).
        showCheckingDelay.stop();
        showChecking = false;
        unlocking = true;
        fade = 1;
        unlockDelay.restart();
    }

    // The copy has drawn its first frame. That frame reaches the screen
    // about 250 ms later (measured, as for the fade-in); letting go of the
    // lock before then showed the bare desktop for a frame.
    function copyDrawn() {
        if (unlocking && locked && !releaseDelay.running)
            releaseDelay.restart();
    }

    // The copy is on screen (or it's taking too long): let go of the lock.
    function releaseLock() {
        if (!unlocking || !locked)
            return;
        unlockDelay.stop();
        releaseDelay.stop();
        locked = false;
        Quickshell.execDetached(["rm", "-f", marker]);
        fadeOut.restart();
    }

    // Leaves `fade` at 0: the copy's window outlives `unlocking` by a frame,
    // and putting it back to 1 here flashed the whole lock screen once.
    function finishUnlock() {
        unlocking = false;
        password = "";
        authState = "";
    }

    property bool unlocking: false
    property real fade: 1

    Timer {
        id: releaseDelay
        interval: 250
        onTriggered: root.releaseLock()
    }

    // A fallback in case the copy never reports a drawn frame.
    Timer {
        id: unlockDelay
        interval: 600
        onTriggered: root.releaseLock()
    }

    // hyprlock's fade-out, measured from a recording: about 0.4 s, half gone
    // in the first 50 ms.
    NumberAnimation {
        id: fadeOut
        target: root
        property: "fade"
        to: 0
        duration: 400
        easing.type: Easing.OutQuart
        onFinished: finishDelay.restart()
    }

    // The copy stays, invisible, for another frame or two before it goes:
    // niri may not draw again once it's gone, and its last drawn frame
    // would keep a trace of the lock.
    Timer {
        id: finishDelay
        interval: 50
        onTriggered: root.finishUnlock()
    }

    function startAuth() {
        if (!(locked || previewing) || pam.active)
            return;
        // A PAM service that won't start would leave no way in: say so and
        // keep trying.
        if (!pam.start()) {
            authState = "failed";
            restartAuth.interval = 2000;
            restartAuth.restart();
        }
    }

    function submit() {
        if (password === "" || authState === "checking" || unlocking)
            return;
        authState = "checking";
        if (pam.responseRequired)
            pam.respond(password);
        else
            pendingPassword = password;
    }

    function failed() {
        restartAuth.interval = 100;
        if (authState === "checking") {
            authState = "failed";
            password = "";
            pendingPassword = "";
        } else {
            // Failing with no password sent means PAM itself is broken:
            // retry slowly, and keep what's being typed.
            restartAuth.interval = 2000;
            if (password === "")
                authState = "failed";
        }
        restartAuth.restart();
    }

    // Start PAM again after a failure: a short pause so the old
    // conversation has fully ended.
    Timer {
        id: restartAuth
        interval: 100
        onTriggered: {
            interval = 100;
            root.startAuth();
        }
    }

    PamContext {
        id: pam

        // Its own PAM service (nixos: security.pam.services.quickshell);
        // hyprlock's until a rebuild has added it, and login's if neither is
        // there.
        // Read up front (blockLoading): a shell restarted while locked starts
        // PAM at once, and its service can't change once started.
        config: quickshellPam.text() !== "" ? "quickshell" : (hyprlockPam.text() !== "" ? "hyprlock" : "login")

        onPamMessage: {
            if (responseRequired && root.pendingPassword !== "") {
                respond(root.pendingPassword);
                root.pendingPassword = "";
            }
        }
        onCompleted: result => {
            if (result !== PamResult.Success)
                root.failed();
            else if (root.locked)
                root.unlock();
            else
                root.previewing = false;
        }
        onError: error => root.failed()
    }

    FileView {
        id: quickshellPam
        path: "/etc/pam.d/quickshell"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: hyprlockPam
        path: "/etc/pam.d/hyprlock"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: markerFile
        path: root.marker
        printErrors: false
        blockWrites: true
    }

    // Read before anything else exists (blockLoading), for `locked` above.
    FileView {
        id: startupMarker
        path: root.marker
        blockLoading: true
        printErrors: false
    }

    // Locked from the start: set up what lock() would have.
    Component.onCompleted: {
        if (locked) {
            refreshBackground();
            startAuth();
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }
        function isLocked(): bool {
            return root.locked;
        }
        function isSecure(): bool {
            return root.locked && root.secure;
        }
        function preview(): void {
            if (root.locked)
                return;
            root.refreshBackground();
            root.password = "";
            root.pendingPassword = "";
            root.authState = "";
            root.previewing = !root.previewing;
            root.startAuth();
        }
    }

    WlSessionLock {
        id: sessionLock

        locked: root.locked

        WlSessionLockSurface {
            color: "black"

            LockSurface {
                id: surface
                anchors.fill: parent
                lock: root
                Component.onCompleted: focusInput()
            }
        }
    }

    // The copy of the lock screen that fades in before locking and out after
    // unlocking, one per screen, above everything.
    Variants {
        model: root.unlocking || root.locking ? Quickshell.screens : []

        PanelWindow {
            id: fadeWindow

            required property var modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // Fading in it holds the mouse and keyboard back from the
            // desktop; fading out it lets them through.
            mask: root.unlocking ? clickThrough : null
            Region {
                id: clickThrough
            }

            WlrLayershell.namespace: "qstest:lockfade"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.locking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // One flattened layer: faded piece by piece, its black backdrop
            // showed through its own wallpaper and darkened the middle of
            // the fade.
            LockSurface {
                anchors.fill: parent
                opacity: root.fade
                layer.enabled: true
                animated: false
                lock: root
            }

            Connections {
                target: fadeWindow.contentItem.Window.window
                function onFrameSwapped() {
                    root.startFadeIn();
                    root.copyDrawn();
                }
            }
        }
    }

    // The same screen in an ordinary overlay, for checking the look: it
    // locks nothing and checks no password.
    PanelWindow {
        visible: root.previewing
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "black"

        WlrLayershell.namespace: "qstest:lockpreview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.previewing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        LockSurface {
            id: previewSurface
            anchors.fill: parent
            lock: root
        }

        onVisibleChanged: {
            if (visible)
                previewSurface.focusInput();
        }
    }
}
