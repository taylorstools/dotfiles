pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Colors, sizes and fonts. The palette is read live from the matugen output
// the Wallpaper service writes (~/.cache/qstest/colors.json) whenever the
// wallpaper changes. Until that file exists, the fallbacks below are used.
// QSTEST_COLORS_FILE can point at another matugen JSON file.
// Sizes are for Taylor's bar (innerPadding 1,
// spacing 0, fixed 12px radius, Inter Medium).
Singleton {
    id: root

    // Palette

    readonly property string colorsFile: Quickshell.env("QSTEST_COLORS_FILE") || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/qstest/colors.json")
    property var _palette: ({})
    readonly property string colorMode: _palette?.mode === "light" ? "light" : "dark"

    // Reads matugen's JSON (colors.primary.dark.color).
    function pick(key, fallback) {
        const colors = root._palette && root._palette.colors;
        if (!colors)
            return fallback;
        return colors[key]?.[root.colorMode]?.color || fallback;
    }

    readonly property color primary: pick("primary", "#b7c8e1")
    readonly property color onPrimary: pick("on_primary", "#21314a")
    readonly property color secondary: pick("secondary", "#bfc6d4")
    readonly property color tertiary: pick("tertiary", "#dcbce0")
    // The light scheme's tertiary whatever the mode: the power menu's resting
    // colour (wlogout's @light, which matugen's own templates still use).
    readonly property color tertiaryLightScheme: root._palette?.colors?.tertiary?.light?.color ?? "#535f70"
    // Backgrounds get Settings.surfaceTint of the tint colour mixed in.
    readonly property color surface: tint(pick("surface", "#111418"))
    readonly property color surfaceText: pick("on_background", "#e1e2e8")
    readonly property color surfaceVariantText: pick("on_surface_variant", "#c4c6cf")
    // The grey fills inside panels (cards, rows, fields, buttons) all come
    // from these three, so Settings.overlayOpacity applies everywhere at once.
    // Panel backgrounds set their own alpha with withAlpha(), so it doesn't
    // touch those.
    readonly property real overlayOpacity: {
        const a = Number(Settings.overlayOpacity);
        return Number.isFinite(a) ? Math.max(0, Math.min(1, a)) : 1;
    }
    readonly property color surfaceContainer: withAlpha(tint(pick("surface_container", "#1d2024")), overlayOpacity)
    readonly property color surfaceContainerHigh: withAlpha(tint(pick("surface_container_high", "#272a2f")), overlayOpacity)
    readonly property color surfaceContainerHighest: withAlpha(tint(pick("surface_container_highest", "#32353a")), overlayOpacity)
    readonly property color outline: pick("outline", "#8e9099")
    readonly property color error: pick("error", "#ffb4ab")

    // Every panel's background uses the one opacity from the settings window.
    // The taskbar and dock use the same colour as the flyouts and panels
    // (surface_container), not the darker surface, so they match where
    // they meet.
    readonly property real surfaceOpacity: Math.max(0.3, Math.min(1, Number(Settings.surfaceOpacity) || 0.8))
    readonly property color barBackground: withAlpha(surfaceContainer, surfaceOpacity)
    readonly property color popupBackground: withAlpha(surfaceContainer, surfaceOpacity)
    readonly property color widgetText: surfaceText
    readonly property color widgetHover: {
        const blended = blend(surfaceContainer, primary, 0.1);
        return withAlpha(blended, Math.max(0.3, blended.a));
    }
    readonly property color primarySelected: withAlpha(primary, 0.3)
    // The border of every panel and flyout (not the taskbar), from
    // Settings > Appearance; primary at 80% by default.
    readonly property color blurBorder: {
        const a = Number(Settings.borderOpacity);
        return withAlpha(namedColor(Settings.borderColor, Settings.borderColorCustom), Number.isFinite(a) ? Math.max(0, Math.min(1, a)) : 0.8);
    }

    FileView {
        id: colorsView
        path: root.colorsFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root._palette = JSON.parse(text());
            } catch (e) {
                console.warn("Theme: could not parse", root.colorsFile, e);
            }
        }
        // On a first run matugen hasn't written the file yet, and a missing
        // file can't be watched, so try again until it shows up.
        onLoadFailed: retryLoad.start()
    }

    Timer {
        id: retryLoad
        interval: 1000
        onTriggered: colorsView.reload()
    }

    // Sizes

    // Bar widget and bar thickness for innerPadding 1. They
    // snap to an even number of physical pixels, so they depend on the
    // screen's scale: at your 1.875 that's 26.67 and 37.33 (50 and 70 px).
    readonly property real dpr: Quickshell.screens.length > 0 ? Quickshell.screens[0].devicePixelRatio : 1
    readonly property real barInnerPadding: 1
    readonly property real widgetThickness: snapEven(Math.max(20, 26 + barInnerPadding * 0.6))
    readonly property real barThickness: snapEven(Math.max(widgetThickness + barInnerPadding + 4, 48 - 4 - (8 - barInnerPadding)))
    // Widget padding: 6 scaled by widgetThickness / 30,
    // snapped to physical pixels (5.33 on your screen).
    readonly property real widgetPadding: snap(6 * widgetThickness / 30)
    // Gap between the bar's ends and its first/last widget.
    readonly property real barEdgeMargin: 4

    readonly property real spacingXXS: 2
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real spacingXL: 24

    readonly property real cornerRadius: 12
    // Panels at the screen edge (control center, calendar flyout, notepad):
    // attached to the taskbar and edge, or floating (Settings.attachPanels).
    readonly property bool attachPanels: Settings.attachPanels
    // Whether the control center, calendar and notepad have a border: always
    // floating, and attached only with Settings.attachedPanelBorder.
    readonly property bool edgePanelBorder: !attachPanels || Settings.attachedPanelBorder
    // The notepad is square when attached.
    readonly property real notepadRadius: attachPanels ? 0 : cornerRadius
    // The control center and calendar keep Settings.flyoutRadius either way.
    // Attached, they reach flyoutOvershoot past the taskbar and the screen
    // edge, so the corners and border on those sides are off screen and only
    // the free top-left corner shows the radius.
    readonly property real flyoutRadius: Math.max(0, Math.min(30, Number(Settings.flyoutRadius ?? 12)))
    readonly property real flyoutOvershoot: attachPanels ? flyoutRadius + 1 : 0

    readonly property real fontSizeSmall: 12
    readonly property real fontSizeMedium: 14
    readonly property real fontSizeLarge: 16
    readonly property real fontSizeXLarge: 20

    readonly property real iconSize: 24
    readonly property real iconSizeLarge: 32

    // Text and icon sizes from the bar thickness.
    function barTextSize(thickness) {
        const scale = thickness / 48;
        if (scale <= 0.75)
            return Math.round(fontSizeSmall * 0.9);
        if (scale >= 1.25)
            return Math.round(fontSizeMedium);
        return Math.round(fontSizeSmall);
    }

    // `offset`: -6 by default, -4 for the control-center icons.
    function barIconSize(thickness, large, offset) {
        const size = large ? iconSizeLarge : iconSize;
        return 2 * Math.round((thickness / 48) * (size + (offset ?? -6)) / 2);
    }

    function snap(value) {
        return Math.round(value * dpr) / dpr;
    }

    // The smallest size at or above `value` that's whole in both logical and
    // physical pixels (a multiple of 8 at scale 1.875). A layer window's size
    // is whole logical pixels; one that isn't whole on screen gets its right
    // or bottom edge shaved off.
    function wholeSize(value) {
        let size = Math.ceil(value - 0.001);
        while (Math.abs(size * dpr - Math.round(size * dpr)) > 0.01 && size < value + 16)
            size++;
        return size;
    }

    function snapEven(value) {
        return 2 * Math.round(value * dpr / 2) / dpr;
    }

    // Animation

    // Every open/close and slide uses this (Settings > Appearance), small
    // touches like switch knobs a bit less. 0 means no animation.
    readonly property int animDuration: {
        const ms = Number(Settings.animationDuration);
        return Number.isFinite(ms) ? Math.max(0, ms) : 110;
    }
    readonly property int animShort: Math.round(animDuration * 0.7)

    // Fonts

    // Settings > Appearance. The default, Inter at medium weight, used to be
    // named here as the family "Inter Medium"; family and weight are separate
    // settings now. Text that sets its own font.family uses these too.
    readonly property string fontFamily: Settings.fontFamily || "Inter"
    readonly property int fontWeight: Settings.fontWeight === "regular" ? Font.Normal : Font.Medium
    readonly property string monoFamily: Settings.monoFontFamily || "monospace"

    // Installed system-wide (nixos components/quickshell.nix).
    readonly property string iconFamily: "Material Symbols Rounded"

    // Helpers

    // For fills that are a bit see-through on purpose: their own alpha,
    // scaled by the overlay opacity setting.
    function overlay(c, a) {
        return withAlpha(c, a * overlayOpacity);
    }

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // A colour setting's value: one of matugen's colours by name, or
    // "custom" for the hex in `custom` (primary while that isn't a valid
    // #rrggbb yet).
    function namedColor(name, custom) {
        switch (name) {
        case "secondary":
            return secondary;
        case "tertiary":
            return tertiary;
        case "outline":
            return outline;
        case "text":
            return surfaceText;
        case "custom":
            return isHexColor(custom) ? Qt.color(normalizeHex(custom)) : primary;
        default:
            return primary;
        }
    }

    // The surface tint colour (Settings > Appearance).
    readonly property color tintColor: namedColor(Settings.surfaceTintColor, Settings.surfaceTintCustom)
    readonly property real tintAmount: Math.max(0, Math.min(1, Number(Settings.surfaceTint) || 0))

    function isHexColor(text) {
        return /^#?[0-9a-fA-F]{6}$/.test(String(text ?? "").trim());
    }

    function normalizeHex(text) {
        const t = String(text).trim();
        return (t.startsWith("#") ? t : "#" + t).toLowerCase();
    }

    function tint(c) {
        // pick() hands back hex strings, so make a colour before mixing.
        // Number(...) || 0 also covers the moment settings.json is reloading.
        return blend(Qt.color(c), tintColor, tintAmount);
    }

    function blend(c1, c2, r) {
        return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r);
    }
}
