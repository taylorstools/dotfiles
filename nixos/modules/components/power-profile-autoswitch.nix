{ config, pkgs, ... }:

let
  powerProfileSwitch = pkgs.writeShellScript "power-profile-switch" ''
    onAc=0
    for ps in /sys/class/power_supply/*; do
      if [ "$(cat "$ps/type" 2>/dev/null)" = "Mains" ] \
         && [ "$(cat "$ps/online" 2>/dev/null)" = "1" ]; then
        onAc=1
      fi
    done

    if [ "$onAc" = "1" ]; then
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
    else
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
    fi
  '';
in
{
  systemd.services.power-profile-switch = {
    description = "Set power profile based on AC/battery state";
    # Also apply the correct profile at boot
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = powerProfileSwitch;
    };
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart power-profile-switch.service"
  '';
}