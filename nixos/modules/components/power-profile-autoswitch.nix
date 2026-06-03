{ config, pkgs, ... }:

let
  powerProfileSwitch = pkgs.writeShellScript "power-profile-switch" ''
    ppctl=${pkgs.power-profiles-daemon}/bin/powerprofilesctl

    # Wait until the daemon is actually serving profiles
    for _ in $(seq 1 30); do
      if timeout 3 "$ppctl" list >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    onAc=0
    for ps in /sys/class/power_supply/*; do
      if [ "$(cat "$ps/type" 2>/dev/null)" = "Mains" ] \
         && [ "$(cat "$ps/online" 2>/dev/null)" = "1" ]; then
        onAc=1
      fi
    done

    if [ "$onAc" = "1" ]; then
      "$ppctl" set performance
    else
      "$ppctl" set power-saver
    fi
  '';
in
{
  systemd.services.power-profile-switch = {
    description = "Set power profile based on AC/battery state";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils pkgs.power-profiles-daemon ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = powerProfileSwitch;
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart power-profile-switch.service"
  '';
}