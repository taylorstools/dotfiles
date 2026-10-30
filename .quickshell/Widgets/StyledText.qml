import QtQuick
import qs.Common

Text {
    color: Theme.widgetText
    font.family: Theme.fontFamily
    font.weight: Theme.fontWeight
    font.pixelSize: Theme.fontSizeMedium
    verticalAlignment: Text.AlignVCenter
    // Glyphs snapped to the pixel grid: crisper at a fractional scale.
    renderType: Text.NativeRendering
}
