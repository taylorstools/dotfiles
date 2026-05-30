{ pkgs, ... }:

let
  tela-custom = pkgs.tela-icon-theme.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${./assets/thunar.svg} $out/share/icons/Tela/scalable/apps/thunar.svg
    '';
  });
in
{
  environment.systemPackages = with pkgs; [
    tela-custom
  ];
}