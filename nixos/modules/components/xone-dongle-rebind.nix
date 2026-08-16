{ pkgs, ... }:

{
  systemd.services.xone-dongle-rebind = {
    description = "Re-bind Xbox Wireless Adapter to clear phantom client";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "xone-dongle-rebind" ''
        set -u
        drv=/sys/bus/usb/drivers/xone-dongle

        # The dongle enumerates ~4s before the module registers; wait for it.
        for _ in $(seq 1 60); do
          for i in "$drv"/*:*; do [ -e "$i" ] && break 2; done
          sleep 1
        done

        found=0
        for i in "$drv"/*:*; do
          [ -e "$i" ] || continue
          n=$(basename "$i")
          found=1
          echo "rebinding $n"
          echo "$n" > "$drv/unbind" || true
          sleep 2
          echo "$n" > "$drv/bind"
        done
        [ "$found" = 1 ] || echo "no xone-dongle interface found, nothing to do"
      '';
    };
  };
}