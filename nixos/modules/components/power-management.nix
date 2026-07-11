{ pkgs, ... }:

{
  imports = [
    ./power-profile-autoswitch.nix
  ];

  services.power-profiles-daemon.enable = true;
  
  systemd.services.powertop-autotune = {
    description = "powertop --auto-tune (boot + resume)";
    wantedBy = [ "multi-user.target" "post-resume.target" ];
    after = [ "post-resume.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
    };
  };
}