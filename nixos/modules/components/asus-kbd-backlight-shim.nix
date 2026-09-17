{ config, pkgs, ... }:

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
  #
  # Suspend has the same blind spot. The keyboard comes back from suspend
  # with its backlight off, and hid-asus's resume hook only restores the
  # level for an LED it registered itself, which here it never did. uleds
  # also only emits an event when the value *changes*, so userspace writing
  # the unchanged level back after resume never reaches this daemon. The
  # resume unit below sends SIGUSR1, and the daemon re-applies its current
  # level a few times while the keyboard settles.
  #
  # Temporary dims (hypridle's idle dim, the lid-close dim) must not become the
  # "last level", or a power-off while dimmed boots with the backlight dark.
  # The dim scripts touch HOLD_PATH before dimming and remove it before
  # restoring; while it exists, levels are applied but not persisted. It lives
  # under /run, so a hold left behind by a power-off is gone on the next boot.
  shim = pkgs.writeText "asus-kbd-backlight-shim.py" ''
    import fcntl
    import glob
    import os
    import select
    import signal
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

    HOLD_PATH = "/run/asus-kbd-backlight-shim/hold"

    VENDOR = "0B05"
    PRODUCT = "19B6"

    # How long to keep retrying a level the keyboard would not take (it may
    # still be re-enumerating after resume), and how often.
    RETRY_SECONDS = 15
    RETRY_INTERVAL = 0.5

    # After resume, re-send the level at these offsets (seconds). The later
    # sends cover a keyboard that accepts a report and then resets itself.
    RESUME_REAPPLY_DELAYS = (0, 2, 5)

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
        # fsync both the file and the directory: an unsynced rename can come
        # back as an empty file after a hard power-off, which reads as 0.
        tmp = STATE_PATH + ".new"
        try:
            with open(tmp, "w") as handle:
                handle.write(str(value) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, STATE_PATH)
            dir_fd = os.open(os.path.dirname(STATE_PATH), os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
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
        # Install the handler first: SIGUSR1's default action would kill us if
        # a resume lands while we are still starting up. set_wakeup_fd turns
        # the signal into something select() can wait on.
        wake_r, wake_w = os.pipe()
        os.set_blocking(wake_r, False)
        os.set_blocking(wake_w, False)
        signal.set_wakeup_fd(wake_w)
        signal.signal(signal.SIGUSR1, lambda signum, frame: None)

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
        # The sends go through the same schedule as a resume: hid-asus may
        # still be probing the keyboard, and a single early send can be lost.
        restored = read_saved()
        print("restoring level " + str(restored))
        sys.stdout.flush()
        if restored and wait_for(
            lambda: os.path.exists(SYSFS_BRIGHTNESS), timeout=10
        ):
            publish(restored)

        current = restored
        saved = restored
        retry_until = 0.0  # non-zero while current still has to reach the keyboard
        now = time.monotonic()
        reapply_at = [now + delay for delay in RESUME_REAPPLY_DELAYS]

        while True:
            now = time.monotonic()
            wakeups = list(reapply_at)
            if retry_until:
                wakeups.append(now + RETRY_INTERVAL)
            timeout = max(0.0, min(wakeups) - now) if wakeups else None
            readable, _, _ = select.select([fd, wake_r], [], [], timeout)
            now = time.monotonic()

            if wake_r in readable:
                try:
                    while os.read(wake_r, 64):
                        pass
                except BlockingIOError:
                    pass
                print("resume: re-applying level " + str(current))
                sys.stdout.flush()
                reapply_at = [now + delay for delay in RESUME_REAPPLY_DELAYS]

            if fd in readable:
                data = os.read(fd, 4)
                if len(data) < 4:
                    break
                current = max(0, min(MAX_BRIGHTNESS, struct.unpack("i", data)[0]))
                retry_until = now + RETRY_SECONDS

            if reapply_at and reapply_at[0] <= now:
                reapply_at = [t for t in reapply_at if t > now]
                retry_until = max(retry_until, now + RETRY_SECONDS)

            if not retry_until:
                continue
            level = round(current * HW_MAX / MAX_BRIGHTNESS)
            if apply_level(level):
                retry_until = 0.0
                if current != saved and not os.path.exists(HOLD_PATH):
                    write_saved(current)
                    saved = current
            elif now >= retry_until:
                retry_until = 0.0
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

  # Nudge the daemon after every resume (see the suspend note above). The
  # leading "-" keeps this quiet on boots where the shim was skipped because
  # the kernel registered the real LED.
  systemd.services.asus-kbd-backlight-shim-resume = {
    description = "Re-apply asus::kbd_backlight level after resume";
    wantedBy = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.systemd}/bin/systemctl kill --kill-whom=main --signal=SIGUSR1 asus-kbd-backlight-shim.service";
    };
  };

  # Where the dim scripts drop the hold marker (see above). Group-writable so
  # they can do it as your user; /run is a tmpfs, so it starts empty each boot.
  systemd.tmpfiles.rules = [
    "d /run/asus-kbd-backlight-shim 0775 root video -"
  ];

  # Both the hold directory and the udev rule below rely on this. It used to
  # arrive only by way of the Howdy module.
  users.users.${config.myOptions.user.name}.extraGroups = [ "video" ];

  # dms/brightnessctl write brightness as your user, not as root.
  services.udev.extraRules = ''
    SUBSYSTEM=="leds", KERNEL=="asus::kbd_backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';
}
