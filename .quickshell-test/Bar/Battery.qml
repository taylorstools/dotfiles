import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Widgets

// Battery glyph + percentage, using DMS's icon ladder. Hidden on machines
// without a battery (the HTPCs).
Item {
    id: root

    property real barThickness: Theme.barThickness

    readonly property var device: UPower.displayDevice
    readonly property bool present: device && device.ready && device.isLaptopBattery
    // UPower reports 0-1 in current Quickshell; older builds used 0-100.
    readonly property real level: {
        if (!device)
            return 0;
        const p = device.percentage;
        return Math.round(p <= 1 ? p * 100 : p);
    }
    readonly property bool charging: device && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: device && device.state === UPowerDeviceState.FullyCharged

    readonly property string icon: {
        if (charging || (full && !UPower.onBattery)) {
            if (level >= 90)
                return "battery_charging_full";
            if (level >= 80)
                return "battery_charging_90";
            if (level >= 60)
                return "battery_charging_80";
            if (level >= 50)
                return "battery_charging_60";
            if (level >= 30)
                return "battery_charging_50";
            if (level >= 20)
                return "battery_charging_30";
            return "battery_charging_20";
        }
        if (level >= 95)
            return "battery_full";
        if (level >= 85)
            return "battery_6_bar";
        if (level >= 70)
            return "battery_5_bar";
        if (level >= 55)
            return "battery_4_bar";
        if (level >= 40)
            return "battery_3_bar";
        if (level >= 25)
            return "battery_2_bar";
        if (level >= 10)
            return "battery_1_bar";
        return "battery_alert";
    }

    visible: present
    implicitWidth: present ? row.implicitWidth + Theme.widgetPadding * 2 : 0
    implicitHeight: barThickness

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingXXS

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: Theme.barIconSize(root.barThickness, false)
            color: root.level < 10 && !root.charging ? Theme.error : Theme.widgetText
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.level + "%"
            font.pixelSize: Theme.barTextSize(root.barThickness)
        }
    }
}
