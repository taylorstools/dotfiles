{ pkgs, ... }:

{
  imports = [
    ./power-profile-autoswitch.nix
  ];

  services.power-profiles-daemon.enable = true;

  # Dims, locks and sleeps when idle (dot_config/hypr/hypridle.conf). Its
  # user unit comes with the package and is started and stopped by
  # scripts/hypridle/toggle-hypridle.sh (keep awake), not enabled here.
  environment.systemPackages = [ pkgs.hypridle ];

  # hypridle's dim/restore scripts call brightnessctl, qs and friends.
  systemd.user.services.hypridle = {
    overrideStrategy = "asDropin";
    serviceConfig.Environment = [
      "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
    ];
  };

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