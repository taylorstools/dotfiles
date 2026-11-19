import QtQuick
import qs.Common
import qs.Services

// The wallpaper blurred and darkened: the overview backdrop
// (Wallpaper/Backdrop.qml), the lock screen and the power menu. It replaces
// ~/.config/.EffectsWallpaper.png, which a script made with
// `magick -fill black -colorize 70% -blur 0x15` seconds after every change,
// and looks the same: against magick's output it's within about 0.5/255 RMS.
//
// The picture is decoded at a third of the screen's size (every copy asks
// for the same size, so they share one decode in Qt's image cache) and
// blurred with a true Gaussian (Shaders/gaussian.frag), across and then down,
// each pass kept in a texture: drawing it costs one scaled texture per frame.
// The whole picture is blurred before it's cropped to the screen, so its
// edges blur as magick's did. Qt's MultiEffect was tried first: its blur keeps
// half the sharp picture mixed in, and fine detail showed through.
//
// magick's sigma is in the picture's own pixels, so a bigger picture gets a
// lighter blur on screen (12.5 px for a 4K one on a 2880x1800 screen, 6 for
// an 8K one); Wallpaper.imageWidths gives the scale.
//
// A new wallpaper fades in over the old one once it has loaded, like the
// desktop's (Wallpaper/Background.qml).
Item {
    id: root

    // Off: draws nothing and holds no picture (the lock's preview while closed).
    property bool active: true
    // The first picture loads on the main thread: the lock's first frame must
    // have it. It's normally already decoded for the backdrop, so that's a
    // cache hit. Later ones always load on another thread.
    property bool asynchronous: true
    // While set, a newly loaded picture waits before fading in: the lock holds
    // it until its colours are ready, so both change together.
    property bool hold: false
    property int fadeDuration: Math.max(0, Number(Settings.wallpaperFadeDuration) || 0)
    // A new picture has started fading in.
    signal fading

    // As the script had it: -blur 0x15, -colorize 70% black.
    readonly property real sigma: 15
    readonly property real dim: 0.3
    readonly property size decodeSize: Qt.size(Math.ceil(Theme.largestScreenPixels.width / 3), Math.ceil(Theme.largestScreenPixels.height / 3))
    // Nothing until the login's wallpaper is decided, as on the desktop.
    readonly property string path: active && !Wallpaper.startupPending ? Wallpaper.path : ""

    clip: true

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // No binding on current.path: it would race this handler.
    onPathChanged: {
        if (current.path === path)
            return;
        fade.stop();
        const onScreen = current.status === Image.Ready || previous.status === Image.Ready;
        if (!onScreen || path === "") {
            previous.path = "";
            current.opacity = 1;
            current.path = path;
            return;
        }
        // Changed again before the last one loaded: keep what's on screen
        // underneath, not a picture that never showed.
        if (current.status === Image.Ready)
            previous.path = current.path;
        current.asynchronous = true;
        current.opacity = 0;
        current.path = path;
    }

    onHoldChanged: tryFade()

    function tryFade() {
        if (current.status === Image.Ready && current.opacity < 1 && !hold && !fade.running) {
            fade.restart();
            fading();
        }
    }

    BlurredPicture {
        id: previous
        decodeSize: root.decodeSize
        sigma: root.sigma
        dim: root.dim
        naturalWidth: Wallpaper.imageWidths[previous.path] ?? 0
    }

    BlurredPicture {
        id: current
        decodeSize: root.decodeSize
        sigma: root.sigma
        dim: root.dim
        naturalWidth: Wallpaper.imageWidths[current.path] ?? 0
        Component.onCompleted: {
            asynchronous = root.asynchronous;
            path = root.path;
        }
        onStatusChanged: root.tryFade()
    }

    NumberAnimation {
        id: fade
        target: current
        property: "opacity"
        to: 1
        duration: root.fadeDuration
        easing.type: Easing.InOutQuad
        onFinished: previous.path = ""
    }

    // One picture, blurred. Gets everything it needs as properties: inline
    // components don't reliably see the ids around them.
    component BlurredPicture: Item {
        id: picture

        property string path: ""
        property alias asynchronous: image.asynchronous
        readonly property alias status: image.status
        property size decodeSize
        property real sigma
        property real dim
        // The picture's own width; 0 until read (then most of them are 3840).
        property int naturalWidth: 0

        // The decoded size, in pixels.
        readonly property real pw: image.implicitWidth
        readonly property real ph: image.implicitHeight
        readonly property real decodedSigma: sigma * pw / (naturalWidth > 0 ? naturalWidth : 3840)

        anchors.fill: parent

        Image {
            id: image
            visible: false
            fillMode: Image.PreserveAspectCrop
            sourceSize: picture.decodeSize
            source: picture.path ? "file://" + picture.path : ""
        }

        ShaderEffect {
            id: across
            visible: false
            width: picture.pw
            height: picture.ph
            property var source: image
            property vector2d texel: Qt.vector2d(1 / Math.max(1, picture.pw), 0)
            property real sigma: picture.decodedSigma
            property real dim: 1
            fragmentShader: Qt.resolvedUrl("../Shaders/gaussian.frag.qsb")
        }

        ShaderEffectSource {
            id: acrossTexture
            visible: false
            width: picture.pw
            height: picture.ph
            sourceItem: across
            textureSize: Qt.size(picture.pw, picture.ph)
        }

        ShaderEffect {
            id: down
            visible: false
            width: picture.pw
            height: picture.ph
            property var source: acrossTexture
            property vector2d texel: Qt.vector2d(0, 1 / Math.max(1, picture.ph))
            property real sigma: picture.decodedSigma
            property real dim: picture.dim
            fragmentShader: Qt.resolvedUrl("../Shaders/gaussian.frag.qsb")
        }

        // What's drawn: the blurred picture, scaled up to cover the screen
        // and centred, as Image.PreserveAspectCrop would.
        ShaderEffectSource {
            readonly property real cover: Math.max(picture.width / Math.max(1, picture.pw), picture.height / Math.max(1, picture.ph))

            visible: image.status === Image.Ready
            sourceItem: down
            textureSize: Qt.size(picture.pw, picture.ph)
            smooth: true
            width: picture.pw * cover
            height: picture.ph * cover
            x: (picture.width - width) / 2
            y: (picture.height - height) / 2
        }
    }
}
