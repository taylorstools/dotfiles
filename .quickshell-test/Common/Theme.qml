pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Colors, sizes and fonts. The palette is read live from the matugen output
// DMS writes (~/.cache/dms/dms-colors.json), so this follows your wallpaper
// the same way DMS does. If that file is missing, the fallbacks below are used.
// Sizes are the values DMS computes for your bar config (innerPadding 1,
// spacing 0, fixed 12px radius, Inter Medium).
Singleton {
    id: root

    // Palette

    readonly property string colorsFile: Quickshell.env("QSTEST_COLORS_FILE") || ((Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/dms/dms-colors.json")
    property var _palette: ({})
    readonly property string colorMode: _palette?.mode === "light" ? "light" : "dark"

    function pick(key, fallback) {
        const colors = root._palette && root._palette.colors;
        const set = colors ? colors[root.colorMode] : null;
        return (set && set[key]) ? set[key] : fallback;
    }

    readonly property color primary: pick("primary", "#b7c8e1")
    readonly property color onPrimary: pick("on_primary", "#21314a")
    readonly property color secondary: pick("secondary", "#bfc6d4")
    readonly property color surface: pick("surface", "#111418")
    readonly property color surfaceText: pick("on_background", "#e1e2e8")
    readonly property color surfaceVariantText: pick("on_surface_variant", "#c4c6cf")
    readonly property color surfaceContainer: pick("surface_container", "#1d2024")
    readonly property color surfaceContainerHigh: pick("surface_container_high", "#272a2f")
    readonly property color surfaceContainerHighest: pick("surface_container_highest", "#32353a")
    readonly property color outline: pick("outline", "#8e9099")
    readonly property color error: pick("error", "#ffb4ab")

    // Derived the same way DMS derives them.
    readonly property color barBackground: withAlpha(surface, Config.barTransparency)
    readonly property color popupBackground: withAlpha(surfaceContainer, Config.popupTransparency)
    readonly property color widgetText: surfaceText
    readonly property color widgetHover: {
        const blended = blend(surfaceContainer, primary, 0.1);
        return withAlpha(blended, Math.max(0.3, blended.a));
    }
    readonly property color primarySelected: withAlpha(primary, 0.3)
    readonly property color blurBorder: withAlpha(primary, 0.8)

    FileView {
        path: root.colorsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._palette = JSON.parse(text());
            } catch (e) {
                console.warn("Theme: could not parse", root.colorsFile, e);
            }
        }
    }

    // Sizes

    readonly property real barThickness: 36
    readonly property real widgetThickness: 28
    readonly property real widgetPadding: 6

    readonly property real spacingXXS: 2
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real spacingXL: 24

    readonly property real cornerRadius: 12

    readonly property real fontSizeSmall: 12
    readonly property real fontSizeMedium: 14
    readonly property real fontSizeLarge: 16
    readonly property real fontSizeXLarge: 20

    readonly property real iconSize: 24
    readonly property real iconSizeLarge: 32

    // Same formulas as DMS's Theme.barTextSize / Theme.barIconSize.
    function barTextSize(thickness) {
        const scale = thickness / 48;
        if (scale <= 0.75)
            return Math.round(fontSizeSmall * 0.9);
        if (scale >= 1.25)
            return Math.round(fontSizeMedium);
        return Math.round(fontSizeSmall);
    }

    function barIconSize(thickness, large) {
        const size = large ? iconSizeLarge : iconSize;
        return 2 * Math.round((thickness / 48) * (size - 6) / 2);
    }

    // Fonts

    readonly property string fontFamily: "Inter Medium"

    // DMS bundles its Material Symbols font instead of installing it, so
    // run.sh finds that file and passes it in. If the font is ever installed
    // system-wide, the plain family name below picks it up instead.
    readonly property string iconFontFile: Quickshell.env("QSTEST_ICON_FONT")
    readonly property string iconFamily: iconFontLoader.status === FontLoader.Ready ? iconFontLoader.name : "Material Symbols Rounded"

    FontLoader {
        id: iconFontLoader
        source: root.iconFontFile ? ("file://" + root.iconFontFile) : ""
    }

    // Helpers

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function blend(c1, c2, r) {
        return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r);
    }
}
