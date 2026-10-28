import QtQuick
import qs.Common

// A Material Symbols Rounded glyph by ligature name, e.g. name: "wifi".
Text {
    id: root

    property string name: ""
    property real size: Theme.iconSize
    property bool filled: false

    text: name
    color: Theme.widgetText
    font.family: Theme.iconFamily
    font.pixelSize: Math.round(size)
    font.hintingPreference: Font.PreferNoHinting
    font.variableAxes: ({
            "FILL": filled ? 1 : 0,
            "GRAD": -25,
            "opsz": 24,
            "wght": filled ? 500 : 400
        })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    width: Math.round(size)
    height: Math.round(size)
}
