{ pkgs, ... }:

let
  remminax11 = pkgs.remmina.overrideAttrs (Old: {
    preFixup = (Old.preFixup or "") + ''
      gappsWrapperArgs+=(
        --set GDK_BACKEND x11
        --set GDK_SCALE 2
        --set GDK_DPI_SCALE 0.5
      )
    '';
  });
in
{
  environment.systemPackages = with pkgs; [
    remminax11
  ];
}