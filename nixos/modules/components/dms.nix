{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.myOptions;
  system = pkgs.stdenv.hostPlatform.system;

  dmsPkg =
    if cfg.dms.source == "git"
    then inputs.dms.packages.${system}.dms-shell
    else pkgs.dms-shell;

  quickshellPkg =
    if cfg.quickshell.source == "git"
    then inputs.quickshell.packages.${system}.default
    else pkgs.quickshell;
in
{
  options.myOptions = {
    dms.source = lib.mkOption {
      type = lib.types.enum [ "stable" "git" ];
      default = "stable";
      description = "Where to source the DankMaterialShell package from.";
    };

    quickshell.source = lib.mkOption {
      type = lib.types.enum [ "stable" "git" ];
      default = "stable";
      description = "Where to source the quickshell package from.";
    };
  };

  config = {
    programs.dank-material-shell = {
      enable = true;
      package = dmsPkg;
      quickshell.package = quickshellPkg;

      systemd = {
        enable = true;
        restartIfChanged = true;
      };

      enableDynamicTheming = true;
      enableClipboardPaste = true;
    };

    environment.systemPackages = with pkgs; [
      accountsservice
      adw-gtk3
      # Also installs hypridle.service into /etc/systemd/user, which is
      # WantedBy=graphical-session.target. That unit is what runs hypridle -
      # nothing spawns it from niri. See dot_config/niri/custom/startup.kdl.
      hypridle
      swaybg
    ];

    # That packaged unit pins Environment=PATH to hypridle's own closure and
    # nothing else: hyprland, hyprlock, procps, coreutils, findutils, gnugrep,
    # gnused, systemd. Every script under ~/scripts/hypridle is
    # #!/usr/bin/env bash, and bash is not on that list, so all of them die
    # with `env: 'bash': No such file or directory` before their first line -
    # silently, since hypridle only logs that the process was created. niri,
    # dms and brightnessctl are missing from it too, so the dim and lock paths
    # would fail on their first real command even with a shell. Put the system
    # profile back: a drop-in is parsed after the unit, and the later
    # assignment of a variable wins.
    systemd.user.services.hypridle = {
      overrideStrategy = "asDropin";
      serviceConfig.Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
}