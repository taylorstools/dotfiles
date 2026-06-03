{ ... }:

{
  imports = [
    #./power-profile-autoswitch.nix
  ];

  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;
}