# xpadneo-idle-shutoff.nix
#
# Powers off Bluetooth-connected Xbox controllers (xpadneo) after a period of
# inactivity, tolerating analog stick and trigger drift.
#
#   Logs:   journalctl -u xpadneo-idle-shutoff -f
#   Status: xpadneo-idle-status
#
# Why this is not just the old xone module with a different sysfs path:
# the xone dongle exposed a GIP "poweroff" write that told the controller to
# shut down. Bluetooth has no host-initiated power-off command at all. The
# closest equivalent is dropping the ACL link via BlueZ, after which the
# controller stops talking to the host and powers itself down on its own
# timer. A controller that is still awake will usually reconnect on its own,
# so a reconnect arriving within `suppressWindow` of a disconnect is granted
# only `reconnectGrace` seconds to produce real input before it is dropped
# again. Real input promotes it straight back to the full idle timeout, so
# picking the controller back up behaves normally.

{ pkgs, ... }:

let
  # Idle seconds before the controller is disconnected.
  idleTimeout = 600;

  # Seconds a controller that reconnected on its own gets to show real input
  # before being dropped again.
  reconnectGrace = 120;

  # How long after a disconnect reconnects stay suppressed.
  suppressWindow = 1800;

  # Seconds between scans for newly connected controllers.
  scanInterval = 5;

  stateDir = "/run/xpadneo-idle-shutoff";
  stateFile = "${stateDir}/state.json";

  xpadneo-idle-shutoff = pkgs.writers.writePython3Bin "xpadneo-idle-shutoff" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [ "E501" ];  # don't fail the build on long lines
  } ''
    """Power off Bluetooth Xbox controllers (xpadneo) after inactivity."""

    import argparse
    import json
    import os
    import select
    import subprocess
    import time

    import evdev

    STATE_FILE = "${stateFile}"
    BLUETOOTHCTL = "${pkgs.bluez}/bin/bluetoothctl"

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


    def mac_from_sysfs(devpath):
        """Fall back to the hci_conn sysfs 'address' file for the BT MAC."""
        node = os.path.realpath("/sys/class/input/" + os.path.basename(devpath))
        while node and node != "/":
            if "bluetooth" in node:
                addr = os.path.join(node, "address")
                if os.path.isfile(addr):
                    try:
                        with open(addr) as f:
                            return f.read().strip()
                    except OSError:
                        return None
            node = os.path.dirname(node)
        return None


    def controller_mac(dev):
        """Bluetooth address for an evdev device, or None if it is not BT."""
        if dev.info.bustype != evdev.ecodes.BUS_BLUETOOTH:
            return None
        uniq = (dev.uniq or "").strip()
        if len(uniq) == 17 and uniq.count(":") == 5:
            return uniq.upper()
        mac = mac_from_sysfs(dev.path)
        return mac.upper() if mac else None


    def find_controllers():
        """Map MAC -> {name, devices} for connected Bluetooth Xbox pads.

        xpadneo can expose more than one evdev node per controller (the pad
        itself plus a consumer-control node for the share button); they all
        share a MAC, so they are grouped and any of them counts as activity.
        """
        found = {}
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            mac = controller_mac(dev) if "Xbox" in dev.name else None
            if not mac:
                dev.close()
                continue
            entry = found.setdefault(mac, {"name": dev.name, "devices": []})
            entry["devices"].append(dev)
        return found


    def close_devices(devices):
        for dev in devices:
            try:
                dev.close()
            except OSError:
                pass


    def disconnect(mac):
        """Drop the ACL link so the controller powers itself down."""
        try:
            proc = subprocess.run(
                [BLUETOOTHCTL, "disconnect", mac],
                capture_output=True, text=True, timeout=20,
            )
        except (OSError, subprocess.SubprocessError) as e:
            log(f"{mac}: bluetoothctl disconnect failed: {e}")
            return False
        out = (proc.stdout + proc.stderr).strip().replace("\n", " | ")
        if proc.returncode == 0:
            log(f"{mac}: disconnected ({out})")
            return True
        log(f"{mac}: disconnect returned {proc.returncode} ({out})")
        return False


    def write_state(controllers, timeout, grace):
        """Atomically write state for `xpadneo-idle-status` to read."""
        payload = {
            "timeout": timeout,
            "grace": grace,
            "controllers": [
                {
                    "mac": mac,
                    "name": c["name"],
                    "last_activity": c["last_wall"],
                    "effective_timeout": c["timeout"],
                }
                for mac, c in sorted(controllers.items())
            ],
        }
        tmp = STATE_FILE + ".tmp"
        try:
            with open(tmp, "w") as f:
                json.dump(payload, f)
            os.replace(tmp, STATE_FILE)
        except OSError as e:
            log(f"Failed to write state: {e}")


    def main():
        ap = argparse.ArgumentParser()
        ap.add_argument("--timeout", type=int, default=600)
        ap.add_argument("--reconnect-grace", type=int, default=120)
        ap.add_argument("--suppress-window", type=int, default=1800)
        ap.add_argument("--scan-interval", type=int, default=5)
        ap.add_argument("--debug", action="store_true",
                        help="log every event that resets the idle timer")
        args = ap.parse_args()

        log(f"xpadneo-idle-shutoff started (timeout={args.timeout}s, "
            f"reconnect-grace={args.reconnect_grace}s, "
            f"suppress-window={args.suppress_window}s)")

        # mac -> {name, devices, last_mono, last_wall, timeout}
        controllers = {}
        # mac -> monotonic time of the disconnect we initiated
        suppressed = {}
        last_scan = 0.0
        last_state_write = 0.0
        write_state(controllers, args.timeout, args.reconnect_grace)

        while True:
            now = time.monotonic()

            if now - last_scan >= args.scan_interval:
                last_scan = now
                changed = False
                for mac, entry in find_controllers().items():
                    if mac in controllers:
                        close_devices(entry["devices"])
                        continue
                    since = now - suppressed.get(mac, float("-inf"))
                    if since < args.suppress_window:
                        timeout = args.reconnect_grace
                        log(f"{mac}: reconnected {int(since)}s after disconnect, "
                            f"granting {timeout}s to show real input")
                    else:
                        timeout = args.timeout
                        suppressed.pop(mac, None)
                        log(f"Watching {entry['name']} ({mac})")
                    controllers[mac] = {
                        "name": entry["name"],
                        "devices": entry["devices"],
                        "last_mono": now,
                        "last_wall": int(time.time()),
                        "timeout": timeout,
                    }
                    changed = True
                if changed:
                    write_state(controllers, args.timeout, args.reconnect_grace)
                    last_state_write = now

            fd_map = {}
            for mac, c in controllers.items():
                for dev in c["devices"]:
                    fd_map[dev.fd] = (mac, dev)

            wait = float(args.scan_interval)
            for c in controllers.values():
                wait = min(wait, c["timeout"] - (time.monotonic() - c["last_mono"]))
            wait = max(0.2, wait)

            ready = []
            if fd_map:
                try:
                    ready, _, _ = select.select(list(fd_map), [], [], wait)
                except (OSError, ValueError):
                    log("select() failed, closing everything and rescanning")
                    for c in controllers.values():
                        close_devices(c["devices"])
                    controllers = {}
                    last_scan = 0.0
                    write_state(controllers, args.timeout, args.reconnect_grace)
                    continue
            else:
                time.sleep(wait)

            active = set()
            dropped = set()
            for fd in ready:
                mac, dev = fd_map[fd]
                try:
                    for ev in dev.read():
                        if is_activity(ev, debug=args.debug):
                            active.add(mac)
                except BlockingIOError:
                    continue
                except OSError:
                    dropped.add(mac)

            for mac in dropped:
                c = controllers.pop(mac, None)
                if c is not None:
                    log(f"{mac}: controller went away, rescanning")
                    close_devices(c["devices"])
                last_scan = 0.0

            promoted = False
            for mac in active:
                c = controllers.get(mac)
                if c is None:
                    continue
                c["last_mono"] = time.monotonic()
                c["last_wall"] = int(time.time())
                if c["timeout"] != args.timeout:
                    log(f"{mac}: real input seen, back to the full {args.timeout}s timeout")
                    c["timeout"] = args.timeout
                    promoted = True
                suppressed.pop(mac, None)

            now = time.monotonic()
            expired = [mac for mac, c in controllers.items()
                       if now - c["last_mono"] >= c["timeout"]]

            for mac in expired:
                c = controllers.pop(mac)
                log(f"{mac}: idle for {int(now - c['last_mono'])}s, "
                    f"disconnecting {c['name']}")
                close_devices(c["devices"])
                disconnect(mac)
                suppressed[mac] = time.monotonic()
                # Give BlueZ a moment before looking for controllers again.
                last_scan = time.monotonic()

            if expired or dropped or promoted:
                write_state(controllers, args.timeout, args.reconnect_grace)
                last_state_write = time.monotonic()
            elif active and time.monotonic() - last_state_write >= 2.0:
                write_state(controllers, args.timeout, args.reconnect_grace)
                last_state_write = time.monotonic()


    if __name__ == "__main__":
        main()
  '';

  xpadneo-idle-status = pkgs.writeShellScriptBin "xpadneo-idle-status" ''
    set -u
    state_file="${stateFile}"
    jq="${pkgs.jq}/bin/jq"

    if [ ! -r "$state_file" ]; then
      echo "xpadneo-idle-shutoff is not running (no state file)"
      exit 1
    fi

    count=$("$jq" '.controllers | length' "$state_file")
    if [ "$count" = "0" ]; then
      echo "No controller currently connected"
      exit 0
    fi

    now=$(date +%s)
    "$jq" -r --argjson now "$now" '
      .controllers[]
      | ($now - .last_activity) as $idle
      | (.effective_timeout - $idle) as $left
      | "\(.name) (\(.mac))",
        "  Idle:      \($idle)s",
        "  Remaining: \(if $left < 0 then 0 else $left end)s (timeout \(.effective_timeout)s)"
    ' "$state_file"
  '';
in {
  environment.systemPackages = [ xpadneo-idle-status ];

  systemd.services.xpadneo-idle-shutoff = {
    description = "Auto power-off Bluetooth Xbox controllers after inactivity (xpadneo)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "bluetooth.service" ];
    after = [ "bluetooth.service" "systemd-udevd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${xpadneo-idle-shutoff}/bin/xpadneo-idle-shutoff"
        + " --timeout ${toString idleTimeout}"
        + " --reconnect-grace ${toString reconnectGrace}"
        + " --suppress-window ${toString suppressWindow}"
        + " --scan-interval ${toString scanInterval}";
      Restart = "on-failure";
      RestartSec = 5;
      # Creates /run/xpadneo-idle-shutoff with mode 0755 so any user can read it.
      RuntimeDirectory = "xpadneo-idle-shutoff";
      RuntimeDirectoryMode = "0755";
    };
  };
}
