{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mission-center
    lm_sensors
  ];

  security.wrappers.nethogs = {
    owner = "root";
    group = "root";
    capabilities = "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe";
    source = "${pkgs.nethogs}/bin/nethogs";
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", RUN+="${pkgs.coreutils}/bin/chmod a+r /sys/%p/energy_uj"
  '';

  boot.kernelModules = [ "coretemp" "nct6775" ];
}