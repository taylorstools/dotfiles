pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The laptop battery, for the bar's battery widget and the battery flyout:
// charge, state, time left and power draw from UPower, plus its health
// (how much it holds now against when new). Power modes are
// power-profiles-daemon's, the same ones powerprofilesctl sets.
Singleton {
    id: root

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
    readonly property bool onBattery: UPower.onBattery
    // Watts, positive either way.
    readonly property real rate: device ? Math.abs(device.changeRate) : 0
    // Seconds until full (charging) or empty, 0 when UPower doesn't know.
    readonly property real timeLeft: !device ? 0 : (charging ? device.timeToFull : (onBattery ? device.timeToEmpty : 0))

    readonly property string status: {
        if (charging)
            return "Charging";
        if (full)
            return "Fully charged";
        return onBattery ? "On battery" : "Plugged in";
    }

    // UPower's own figure when it has one, otherwise energy_full over
    // energy_full_design from sysfs. 0 when neither is known.
    readonly property real health: {
        const d = laptopBattery;
        if (d && d.healthSupported && d.healthPercentage > 0)
            return Math.round(d.healthPercentage);
        return sysfsHealth;
    }
    readonly property var laptopBattery: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property string sysfsDir: "/sys/class/power_supply/" + (laptopBattery?.nativePath || "BAT0")
    readonly property real sysfsHealth: {
        const now = parseFloat(energyFull.text()) || parseFloat(chargeFull.text());
        const design = parseFloat(energyDesign.text()) || parseFloat(chargeDesign.text());
        return now > 0 && design > 0 ? Math.round(now / design * 100) : 0;
    }

    // Material Symbols battery glyphs by level.
    readonly property string icon: {
        if (charging || (full && !onBattery)) {
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

    // "5 h 36 min", "42 min"
    function formatTime(seconds) {
        const minutes = Math.round(seconds / 60);
        if (minutes < 60)
            return minutes + " min";
        return Math.floor(minutes / 60) + " h " + (minutes % 60) + " min";
    }

    // Power modes: "power-saver", "balanced" or "performance", as
    // powerprofilesctl names them.
    readonly property string powerMode: {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver:
            return "power-saver";
        case PowerProfile.Performance:
            return "performance";
        default:
            return "balanced";
        }
    }
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    function setPowerMode(mode) {
        switch (mode) {
        case "power-saver":
            PowerProfiles.profile = PowerProfile.PowerSaver;
            break;
        case "performance":
            PowerProfiles.profile = PowerProfile.Performance;
            break;
        default:
            PowerProfiles.profile = PowerProfile.Balanced;
        }
    }

    FileView {
        id: energyFull
        path: root.sysfsDir + "/energy_full"
        printErrors: false
    }
    FileView {
        id: energyDesign
        path: root.sysfsDir + "/energy_full_design"
        printErrors: false
    }
    FileView {
        id: chargeFull
        path: root.sysfsDir + "/charge_full"
        printErrors: false
    }
    FileView {
        id: chargeDesign
        path: root.sysfsDir + "/charge_full_design"
        printErrors: false
    }
}
