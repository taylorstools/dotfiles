{ pkgs, ... }:

let
  settleSeconds = 25;

  rebindScript = pkgs.writeShellScript "xone-dongle-rebind" ''
    set -u
    export PATH=${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin
    drv=/sys/bus/usb/drivers/xone-dongle

    iface() {
      for i in "$drv"/*:*; do
        [ -e "$i" ] && { basename "$i"; return 0; }
      done
      return 1
    }

    has_real_controller() {
      grep -qi xbox /sys/class/input/input*/name 2>/dev/null
    }

    active_count() {
      for f in "$drv"/*/active_clients; do
        [ -e "$f" ] || continue
        head -1 "$f" | awk '{print $NF}'
        return 0
      done
      echo 0
    }

    # Phantom client: dongle reports a client, no evdev node exists for it.
    is_wedged() {
      c=$(active_count)
      case "$c" in *[!0-9]*|"") return 1 ;; esac
      [ "$c" -gt 0 ] && ! has_real_controller
    }

    for _ in $(seq 1 60); do
      iface >/dev/null 2>&1 && break
      sleep 1
    done

    # Capture the name now -- it vanishes from the driver dir after unbind.
    n=$(iface 2>/dev/null) || { echo "no xone-dongle interface found"; exit 0; }

    sleep ${toString settleSeconds}

    attempt=1
    while [ "$attempt" -le 3 ]; do
      if ! is_wedged; then
        echo "dongle healthy before attempt $attempt, done"
        exit 0
      fi
      echo "wedged, rebinding $n (attempt $attempt)"
      echo "$n" > "$drv/unbind" 2>/dev/null || true
      sleep 3
      echo "$n" > "$drv/bind" 2>/dev/null || true
      sleep 8
      attempt=$((attempt + 1))
    done

    if is_wedged; then
      echo "still wedged after 3 attempts"
      exit 1
    fi
    echo "recovered"
  '';
in
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "xone-rebind" ''exec ${rebindScript}'')
  ];

  systemd.services.xone-dongle-rebind = {
    description = "Re-bind Xbox Wireless Adapter to clear phantom client";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      # "exec" rather than "oneshot" so the 25s settle doesn't delay
      # multi-user.target being reached.
      Type = "exec";
      ExecStart = rebindScript;
    };
  };
}