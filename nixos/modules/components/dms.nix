{ config, pkgs, inputs, ... }:

{
  programs.dank-material-shell = {
    enable = true;

    quickshell.package = inputs.quickshell.packages.${pkgs.system}.default;

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
}