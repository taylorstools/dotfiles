{ pkgs, ... }:

let
  ryzenadj-latest = pkgs.ryzenadj.overrideAttrs (old: {
    version = "0.19.0";
    src = pkgs.fetchFromGitHub {
      owner = "FlyGoat";
      repo = "RyzenAdj";
      rev = "v0.19.0";
      hash = "sha256-SNtCKZ3bugawzD8R3DjwPs/ls3kyTw1LdIcXuR6fumc=";
    };
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.pkg-config ];
  });

  coMagnitude = 25;
  coall = 1048576 - coMagnitude; # 0x100000 - coMagnitude

  ryzenadjBin = "${ryzenadj-latest}/bin/ryzenadj";
in
{
  hardware.cpu.amd.ryzen-smu.enable = true;

  environment.systemPackages = [ ryzenadj-latest ];

  systemd.services.ryzenadj = {
    description = "ryzenadj power limits + Curve Optimizer undervolt";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Two separate calls so each shows independently in the journal
      ExecStart = [
        # Power limits (mW) + thermal cap (C). These are PX13 stock values;
        # lower stapm-limit / slow-limit for cooler running and longer battery.
        "${ryzenadjBin} --stapm-limit=45000 --fast-limit=85000 --slow-limit=50000 --tctl-temp=95"
        # All-core undervolt (magnitude from coMagnitude above).
        "${ryzenadjBin} --set-coall=${toString coall}"
      ];
    };
  };

  # Reapply on resume
  powerManagement.resumeCommands = "${pkgs.systemd}/bin/systemctl restart ryzenadj.service";
}