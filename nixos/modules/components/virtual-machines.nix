{ pkgs, ... }:

let
  rdpHost = { Name, Host, User }:
    pkgs.makeDesktopItem {
      name = "rdp-${Name}";
      desktopName = "RDP: ${Name}";
      icon = "preferences-desktop-remote-desktop";
      exec = "${pkgs.freerdp}/bin/sdl-freerdp3 /v:${Host} /u:${User} "
           + "/clipboard /dynamic-resolution /sound /cert:ignore";
    };
in {
  environment.systemPackages = [
    pkgs.freerdp
    (rdpHost { Name = "win11vm"; Host = "192.168.0.4"; User = "taylor"; })
  ];
}