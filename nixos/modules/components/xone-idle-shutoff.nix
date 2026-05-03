{ config, lib, pkgs, ... }:

let
  # Idle seconds before the controller is powered off.
  idleTimeout = 600;

  xone-idle-shutoff = pkgs.writers.writePython3Bin "xone-idle-shutoff" {
    libraries = [ pkgs.python3Packages.evdev ];
  } ''
    """Power off xone-managed Xbox controllers after a period of inactivity."""

    import argparse
    import glob
    import select
    import time

    import evdev

    XONE_POWEROFF_GLOB = "/sys/bus/usb/drivers/xone-dongle/*/poweroff"


    def log(msg):
        print(msg, flush=True)


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
        args = ap.parse_args()

        log(f"xone-idle-shutoff started (timeout={args.timeout}s)")
        devices = []
        last_activity = None

        while True:
            # (Re)discover controllers if we don't have any
            if not devices:
                devices = find_controllers()
                if not devices:
                    time.sleep(args.scan_interval)
                    continue
                log(f"Watching: {[d.name for d in devices]}")
                last_activity = time.monotonic()

            fd_map = {d.fd: d for d in devices}
            elapsed = time.monotonic() - last_activity
            wait = max(1.0, args.timeout - elapsed)

            try:
                ready, _, _ = select.select(fd_map.keys(), [], [], wait)
            except (OSError, ValueError):
                # fd became invalid, controller almost certainly disconnected
                close_all(devices)
                devices = []
                last_activity = None
                continue

            if ready:
                activity = False
                disconnected = False
                for fd in ready:
                    try:
                        for ev in fd_map[fd].read():
                            # Ignore SYN events; they accompany every real event
                            if ev.type != evdev.ecodes.EV_SYN:
                                activity = True
                    except OSError:
                        disconnected = True
                        break
                if disconnected:
                    log("Controller disconnected, rescanning")
                    close_all(devices)
                    devices = []
                    last_activity = None
                elif activity:
                    last_activity = time.monotonic()
            else:
                # select timed out -> we're past the idle threshold
                log(f"Idle for {args.timeout}s, powering off")
                power_off_all()
                close_all(devices)
                devices = []
                last_activity = None
                time.sleep(2)  # let the dongle settle before rescanning


    if __name__ == "__main__":
        main()
  '';
in {
  systemd.services.xone-idle-shutoff = {
    description = "Auto power-off Xbox controllers after inactivity (xone)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${xone-idle-shutoff}/bin/xone-idle-shutoff --timeout ${toString idleTimeout}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}