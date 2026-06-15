import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "betterRunningApps"

    StyledText {
        width: parent.width
        text: "Better Running Apps"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Controls how app labels shrink when many windows are open so the widget does not overflow the right-side widgets."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "maxWidthPercent"
        label: "Max bar coverage"
        description: "How much of the screen width running apps may fill before labels start shrinking."
        defaultValue: 60
        minimum: 30
        maximum: 100
        unit: "%"
    }

    SliderSetting {
        settingKey: "maxRunningAppsWidth"
        label: "Hard width cap"
        description: "Absolute width limit in pixels. Set to 0 to use the percentage above instead."
        defaultValue: 0
        minimum: 0
        maximum: 4000
        unit: "px"
    }

    SliderSetting {
        settingKey: "fullTitleWidth"
        label: "Full label width"
        description: "Width of each app's label when there is plenty of room."
        defaultValue: 120
        minimum: 40
        maximum: 300
        unit: "px"
    }

    SliderSetting {
        settingKey: "minTitleWidth"
        label: "Minimum label width"
        description: "If a label would be narrower than this, that app shows as icon-only instead of a tiny slice of text. 0 disables (always show labels)."
        defaultValue: 48
        minimum: 0
        maximum: 200
        unit: "px"
    }

    SliderSetting {
        settingKey: "reservedBarWidth"
        label: "Reserved right-side space"
        description: "Extra pixels to keep free (e.g. for the right-side widget cluster) when using the percentage budget."
        defaultValue: 0
        minimum: 0
        maximum: 2000
        unit: "px"
    }
}
