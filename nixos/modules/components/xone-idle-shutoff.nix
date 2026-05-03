# xone-idle-shutoff.nix
#
# Drop this file next to your configuration.nix and add it to imports:
#
#   imports = [ ./xone-idle-shutoff.nix ];
#
# Then `sudo nixos-rebuild switch`.
#   Logs:   journalctl -u xone-idle-shutoff -f
#   Status: xone-idle-status

{ config, lib, pkgs, ... }:

let
  # Idle seconds before the controller is powered off.
  # Xbox default on Windows is 15 minutes (900s).
  idleTimeout = 600;

  stateDir = "/run/xone-idle-shutoff";
  stateFile = "${stateDir}/last-activity";

  xone-idle-shutoff = pkgs.writers.writePython3Bin "xone-idle-shutoff" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [ "E501" ];  # don't faill the build on long lines
  } ''
    """Power off xone-managed Xbox controllers after a period of inactivity."""

    import argparse
    import glob
    import os
    import select
    import time

    import evdev

    XONE_POWEROFF_GLOB = "/sys/bus/usb/drivers/xone-dongle/*/poweroff"
    STATE_FILE = "${stateFile}"

    # ABS axis groups for activity filtering.
    # Sticks rest at 0 with range roughly -32768..32767. Drift is small.
    # Triggers rest at 0 with range 0..1023.
    # The dpad emits discrete -1/0/+1 values, so any nonzero is a real press.
    STICK_AXES = {
        evdev.ecodes.ABS_X, evdev.ecodes.ABS_Y,
        evdev.ecodes.ABS_RX, evdev.ecodes.ABS_RY,
    }
    TRIGGER_AXES = {evdev.ecodes.ABS_Z, evdev.ecodes.ABS_RZ}
    DPAD_AXES = {evdev.ecodes.ABS_HAT0X, evdev.ecodes.ABS_HAT0Y}

    # Thresholds. Anything below these on a stick/trigger axis is treated
    # as drift/noise and ignored for activity detection.
    STICK_THRESHOLD = 6000     # ~18% of full range, well above typical drift
    TRIGGER_THRESHOLD = 80     # ~8% of trigger range


    def log(msg):
        print(msg, flush=True)


    def is_activity(ev, debug=False):
        """Decide whether an evdev event counts as 'user activity'."""
        if ev.type == evdev.ecodes.EV_KEY:
            # Buttons - always intentional
            if debug:
                log(f"activity: KEY code={ev.code} value={ev.value}")
            return True
        if ev.type == evdev.ecodes.EV_ABS:
            if ev.code in STICK_AXES:
                if abs(ev.value) > STICK_THRESHOLD:
                    if debug:
                        log(f"activity: STICK code={ev.code} value={ev.value}")
                    return True
                return False
            if ev.code in TRIGGER_AXES:
                if ev.value > TRIGGER_THRESHOLD:
                    if debug:
                        log(f"activity: TRIGGER code={ev.code} value={ev.value}")
                    return True
                return False
            if ev.code in DPAD_AXES:
                if ev.value != 0:
                    if debug:
                        log(f"activity: DPAD code={ev.code} value={ev.value}")
                    return True
                return False
            # Unknown ABS axis - ignore (better to miss real input than to
            # be reset by chatter we don't understand).
            return False
        # EV_SYN, EV_MSC, EV_FF (force feedback echoes), etc. - never activity.
        return False


    def write_state(last_activity_wall, watching):
        """Atomically write current state for `xone-idle-status` to read."""
        try:
            tmp = STATE_FILE + ".tmp"
            with open(tmp, "w") as f:
                # line 1: wall-clock unix timestamp of last activity (or "none")
                # line 2: 1 if a controller is currently being watched, else 0
                f.write(f"{last_activity_wall if last_activity_wall else 'none'}\n")
                f.write(f"{1 if watching else 0}\n")
            os.replace(tmp, STATE_FILE)
        except OSError as e:
            log(f"Failed to write state: {e}")


    def find_controllers():
        devs = []
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            # xone exposes controllers with "Xbox" in the evdev name
            if "Xbox" in dev.name:
                devs.append(dev)
            else:
                dev.close()
        return devs


    def power_off_all():
        paths = glob.glob(XONE_POWEROFF_GLOB)
        if not paths:
            log("No xone-dongle sysfs entry found; skipping power off")
            return
        for path in paths:
            try:
                with open(path, "w") as f:
                    f.write("-1")  # -1 == power off all connected clients
                log(f"Sent poweroff via {path}")
            except OSError as e:
                log(f"Failed to write {path}: {e}")


    def close_all(devs):
        for d in devs:
            try:
                d.close()
            except Exception:
                pass


    def main():
        ap = argparse.ArgumentParser()
        ap.add_argument("--timeout", type=int, default=900)
        ap.add_argument("--scan-interval", type=int, default=5)
        ap.add_argument("--debug", action="store_true",
                        help="log every event that resets the idle timer")
        args = ap.parse_args()

        log(f"xone-idle-shutoff started (timeout={args.timeout}s)")
        devices = []
        # We track activity with monotonic time internally (immune to clock
        # jumps) but also stamp the state file with wall time so that the
        # `xone-idle-status` helper can just diff against `date +%s`.
        last_activity_mono = None
        last_activity_wall = None
        write_state(None, watching=False)

        while True:
            # (Re)discover controllers if we don't have any
            if not devices:
                devices = find_controllers()
                if not devices:
                    write_state(None, watching=False)
                    time.sleep(args.scan_interval)
                    continue
                log(f"Watching: {[d.name for d in devices]}")
                last_activity_mono = time.monotonic()
                last_activity_wall = int(time.time())
                write_state(last_activity_wall, watching=True)

            fd_map = {d.fd: d for d in devices}
            elapsed = time.monotonic() - last_activity_mono
            wait = max(1.0, args.timeout - elapsed)

            try:
                ready, _, _ = select.select(fd_map.keys(), [], [], wait)
            except (OSError, ValueError):
                # fd became invalid, controller almost certainly disconnected
                close_all(devices)
                devices = []
                last_activity_mono = None
                last_activity_wall = None
                write_state(None, watching=False)
                continue

            if ready:
                activity = False
                disconnected = False
                for fd in ready:
                    try:
                        for ev in fd_map[fd].read():
                            if is_activity(ev, debug=args.debug):
                                activity = True
                    except OSError:
                        disconnected = True
                        break
                if disconnected:
                    log("Controller disconnected, rescanning")
                    close_all(devices)
                    devices = []
                    last_activity_mono = None
                    last_activity_wall = None
                    write_state(None, watching=False)
                elif activity:
                    last_activity_mono = time.monotonic()
                    last_activity_wall = int(time.time())
                    write_state(last_activity_wall, watching=True)
            else:
                # select timed out -> we're past the idle threshold
                log(f"Idle for {args.timeout}s, powering off")
                power_off_all()
                close_all(devices)
                devices = []
                last_activity_mono = None
                last_activity_wall = None
                write_state(None, watching=False)
                time.sleep(2)  # let the dongle settle before rescanning


    if __name__ == "__main__":
        main()
  '';

  xone-idle-status = pkgs.writeShellScriptBin "xone-idle-status" ''
    set -u
    state_file="${stateFile}"
    timeout=${toString idleTimeout}

    if [ ! -r "$state_file" ]; then
      echo "xone-idle-shutoff service not running (no state file)"
      exit 1
    fi

    ts=$(sed -n '1p' "$state_file")
    watching=$(sed -n '2p' "$state_file")

    if [ "$watching" != "1" ] || [ "$ts" = "none" ] || [ -z "$ts" ]; then
      echo "No controller currently connected"
      exit 0
    fi

    now=$(date +%s)
    idle=$(( now - ts ))
    remaining=$(( timeout - idle ))
    if [ "$remaining" -lt 0 ]; then remaining=0; fi

    printf 'Idle:      %ds\n'  "$idle"
    printf 'Remaining: %ds (timeout %ds)\n' "$remaining" "$timeout"
  '';
in {
  environment.systemPackages = [ xone-idle-status ];

  systemd.services.xone-idle-shutoff = {
    description = "Auto power-off Xbox controllers after inactivity (xone)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${xone-idle-shutoff}/bin/xone-idle-shutoff --timeout ${toString idleTimeout}";
      Restart = "on-failure";
      RestartSec = 5;
      # Creates /run/xone-idle-shutoff with mode 0755 so any user can read it.
      RuntimeDirectory = "xone-idle-shutoff";
      RuntimeDirectoryMode = "0755";
    };
  };
}
