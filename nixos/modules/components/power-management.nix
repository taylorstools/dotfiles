{ pkgs, ... }:

{
  imports = [
    ./power-profile-autoswitch.nix
  ];

  services.power-profiles-daemon.enable = true;

  systemd.services.powertop-autotune = {
    description = "powertop --auto-tune (boot + resume)";
    wantedBy = [
      "multi-user.target"
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
    };
  };
}