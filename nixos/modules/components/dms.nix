{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.myOptions;
  system = pkgs.stdenv.hostPlatform.system;

  dmsBasePkg =
    if cfg.dms.source == "git"
    then inputs.dms.packages.${system}.dms-shell
    else pkgs.dms-shell;

  # Windows-style tray: treat every tray item as "hidden" so nothing sits on
  # the bar and everything lives behind the chevron popout. isHiddenTrayId()
  # is only consumed by SystemTrayBar.qml, so this has no other side effects.
  dmsPkg =
    if cfg.dms.collapseTray
    then dmsBasePkg.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/share/quickshell/dms/Common/SessionData.qml \
          --replace-fail \
            'return trayId && hiddenTrayIds.indexOf(trayId) !== -1;' \
            'return !!trayId;'
      '';
    })
    else dmsBasePkg;

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

    dms.collapseTray = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Collapse every system tray icon behind the tray chevron (Windows-style).";
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
      hypridle
      swaybg
    ];

    systemd.user.services.hypridle = {
      overrideStrategy = "asDropin";
      serviceConfig.Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
}