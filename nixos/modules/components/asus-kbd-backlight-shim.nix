{ pkgs, ... }:

let
  # hid-asus on this machine fails to bring up the keyboard backlight:
  #   asus 0003:0B05:19B6.0002: Asus failed to request functions: -75
  #   asus 0003:0B05:19B6.0002: Failed to initialize backlight.
  # -75 is -EOVERFLOW on the GET_REPORT half of asus_kbd_get_functions, so no
  # LED class device is ever registered. The brightness *write* path is fine,
  # so this daemon registers a uleds device under the name the kernel would
  # have used and forwards writes to the keyboard over hidraw. Everything that
  # speaks to /sys/class/leds (dms, brightnessctl, logind) then works unchanged.
  #
  # A uleds LED is a virtual device with no ID_PATH, so systemd's
  # 99-systemd.rules never matches it and systemd-backlight@leds:... is never
  # pulled in - nothing saves or restores the level across reboots. The daemon
  # therefore keeps its own state file and re-applies it at startup.
  shim = pkgs.writeText "asus-kbd-backlight-shim.py" ''
    import fcntl
    import glob
    import os
    import struct
    import sys
    import time

    LED_NAME = "asus::kbd_backlight"
    SYSFS_BRIGHTNESS = "/sys/class/leds/" + LED_NAME + "/brightness"

    # Levels the keyboard controller actually understands.
    HW_MAX = 3

    # What the LED advertises to userspace. Keep it at HW_MAX to mirror what
    # the kernel driver would have exposed; raise it to 100 if you would rather
    # dms deal in whole percentages (the daemon scales down to HW_MAX either
    # way, so nothing else needs to change).
    MAX_BRIGHTNESS = HW_MAX

    LED_MAX_NAME_SIZE = 64

    VENDOR = "0B05"
    PRODUCT = "19B6"

    # Same feature report hid-asus uses in asus_kbd_backlight_set().
    REPORT_PREFIX = [0x5A, 0xBA, 0xC5, 0xC4]

    # StateDirectory= gives us /var/lib/asus-kbd-backlight-shim.
    STATE_PATH = os.path.join(
        os.environ.get("STATE_DIRECTORY", "/var/lib/asus-kbd-backlight-shim"),
        "brightness",
    )


    def hidiocsfeature(length):
        return 0xC0000000 | (length << 16) | (0x48 << 8) | 0x06


    def keyboard_nodes():
        nodes = []
        for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            try:
                with open(os.path.join(path, "device", "uevent")) as handle:
                    raw = handle.read()
            except OSError:
                continue
            fields = dict(
                line.split("=", 1)
                for line in raw.strip().splitlines()
                if "=" in line
            )
            hid_id = fields.get("HID_ID", "").upper()
            if VENDOR in hid_id and PRODUCT in hid_id:
                nodes.append("/dev/" + os.path.basename(path))
        return nodes


    def apply_level(level):
        payload = bytearray(REPORT_PREFIX + [level])
        delivered = False
        for node in keyboard_nodes():
            try:
                fd = os.open(node, os.O_RDWR)
            except OSError:
                continue
            try:
                fcntl.ioctl(fd, hidiocsfeature(len(payload)), payload)
                delivered = True
            except OSError:
                pass
            finally:
                os.close(fd)
        return delivered


    def read_saved():
        try:
            with open(STATE_PATH) as handle:
                value = int(handle.read().strip())
        except (OSError, ValueError):
            return 0
        return max(0, min(MAX_BRIGHTNESS, value))


    def write_saved(value):
        tmp = STATE_PATH + ".new"
        try:
            with open(tmp, "w") as handle:
                handle.write(str(value) + "\n")
            os.replace(tmp, STATE_PATH)
        except OSError as err:
            print("could not persist level: " + str(err), file=sys.stderr)
            sys.stdout.flush()


    def publish(value):
        # Writing our own sysfs node keeps the value userspace reads in step
        # with the hardware; the write comes back around through /dev/uleds and
        # is applied by the main loop.
        try:
            with open(SYSFS_BRIGHTNESS, "w") as handle:
                handle.write(str(value))
        except OSError as err:
            print("could not seed sysfs brightness: " + str(err), file=sys.stderr)
            sys.stdout.flush()


    def wait_for(predicate, timeout=60):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(1)
        return predicate()


    def main():
        if not wait_for(keyboard_nodes):
            print("no ASUS N-Key hidraw node appeared", file=sys.stderr)
            return 1
        if not wait_for(lambda: os.path.exists("/dev/uleds")):
            print("/dev/uleds missing - is the uleds module loaded?", file=sys.stderr)
            return 1

        fd = os.open("/dev/uleds", os.O_RDWR)
        name = LED_NAME.encode()[:LED_MAX_NAME_SIZE - 1]
        os.write(
            fd,
            name.ljust(LED_MAX_NAME_SIZE, b"\0") + struct.pack("i", MAX_BRIGHTNESS),
        )
        print("registered " + LED_NAME + ", max_brightness " + str(MAX_BRIGHTNESS))
        sys.stdout.flush()

        # The LED always comes up at 0, so put the level back where it was
        # before the last shutdown instead of leaving the backlight dark.
        restored = read_saved()
        apply_level(round(restored * HW_MAX / MAX_BRIGHTNESS))
        print("restored level " + str(restored))
        sys.stdout.flush()
        if restored and wait_for(
            lambda: os.path.exists(SYSFS_BRIGHTNESS), timeout=10
        ):
            publish(restored)

        while True:
            data = os.read(fd, 4)
            if len(data) < 4:
                break
            requested = max(0, min(MAX_BRIGHTNESS, struct.unpack("i", data)[0]))
            level = round(requested * HW_MAX / MAX_BRIGHTNESS)
            if apply_level(level):
                write_saved(requested)
            else:
                print("could not deliver level " + str(level), file=sys.stderr)
                sys.stdout.flush()

        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';
in
{
  boot.kernelModules = [ "uleds" ];

  systemd.services.asus-kbd-backlight-shim = {
    description = "Userspace asus::kbd_backlight LED (hid-asus backlight init fails on this machine)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];

    # If a future kernel registers the real LED, this unit stays out of the way
    # rather than creating a colliding asus::kbd_backlight_1.
    unitConfig.ConditionPathExists = "!/sys/class/leds/asus::kbd_backlight";

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${shim}";
      Restart = "on-failure";
      RestartSec = 5;
      StateDirectory = "asus-kbd-backlight-shim";
    };
  };

  # dms/brightnessctl write brightness as your user, not as root.
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="asus::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';
}
