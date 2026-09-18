import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "BetterRunningApps"

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

    ToggleSetting {
        settingKey: "largeIcons"
        label: "Larger app icons"
        description: "Use the large bar icon size. On by default because that is what this widget has always rendered."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "currentWorkspaceOnly"
        label: "Current workspace only"
        description: "Show only windows on the workspace you are looking at. Off, matching the DMS global this replaces."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "groupByApp"
        label: "Group windows by app"
        description: "Collapse each app's windows into one entry with a count badge."
        defaultValue: false
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
