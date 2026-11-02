{ pkgs, ... }:

{
  imports = [
    ./power-profile-autoswitch.nix
  ];

  services.power-profiles-daemon.enable = true;

  # Dims, locks and sleeps when idle (dot_config/hypr/hypridle.conf). Its
  # user unit comes with the package; scripts/hypridle/toggle-hypridle.sh
  # (keep awake) stops and starts it for the rest of the session.
  environment.systemPackages = [ pkgs.hypridle ];

  systemd.user.services.hypridle = {
    overrideStrategy = "asDropin";
    # NixOS ignores a packaged unit's [Install] section, so its
    # WantedBy=graphical-session.target does nothing without this.
    wantedBy = [ "graphical-session.target" ];
    # hypridle's dim/restore scripts call brightnessctl, qs and friends.
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