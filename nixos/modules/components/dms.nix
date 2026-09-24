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
  #
  # Two packaging layouts to handle:
  #   - nixpkgs (>= 1.6): QML is embedded in the Go binary via `make sync-shell`
  #     in preBuild, so patch the source tree in postPatch.
  #   - DMS flake: QML is copied to $out/share/quickshell/dms in postInstall,
  #     so patch the installed copy.
  # Fails the build if neither location had the file, so an upstream layout
  # change can't silently drop the patch.
  trayFind = "return trayId && hiddenTrayIds.indexOf(trayId) !== -1;";
  trayRepl = "return !!trayId;";

  dmsPkg =
    if cfg.dms.collapseTray
    then dmsBasePkg.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        trayQml=../quickshell/Common/SessionData.qml
        if [ -f "$trayQml" ]; then
          chmod u+w "$(dirname "$trayQml")" "$trayQml"
          substituteInPlace "$trayQml" --replace-fail '${trayFind}' '${trayRepl}'
          touch "$NIX_BUILD_TOP/.dms-tray-patched"
        fi
      '';
      postInstall = (old.postInstall or "") + ''
        trayQml=$out/share/quickshell/dms/Common/SessionData.qml
        if [ -f "$trayQml" ]; then
          substituteInPlace "$trayQml" --replace-fail '${trayFind}' '${trayRepl}'
          touch "$NIX_BUILD_TOP/.dms-tray-patched"
        fi
        if [ ! -e "$NIX_BUILD_TOP/.dms-tray-patched" ]; then
          echo "dms.collapseTray: SessionData.qml not found; tray patch not applied" >&2
          exit 1
        fi
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