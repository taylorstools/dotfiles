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
  };
}