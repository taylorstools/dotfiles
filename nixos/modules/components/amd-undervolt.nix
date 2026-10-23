{ config, lib, pkgs, ... }:

let
  kernel = config.boot.kernelPackages.kernel;

  # TEMP(nixpkgs-2026-10): nixpkgs now signs every kernel module with kmodigest during
  # `make modules_install` and aggregates the per-module `<mod>.ko.cer`
  # files into modules.cer, which gets baked into the kernel image. The
  # ryzen-smu package installs its .ko by hand, so it never gets signed and
  # the modules aggregator dies on `cat ryzen_smu.ko.cer: No such file`.
  # Sign it ourselves. postFixup so it runs after strip, which would
  # otherwise mangle the appended signature. Fixed on nixpkgs master (the
  # package now uses modules_install); once that reaches the channel the
  # .ko.cer already exists and this skips itself. Then drop it and go back
  # to hardware.cpu.amd.ryzen-smu.enable.
  ryzenSmu = config.boot.kernelPackages.ryzen-smu.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      ko=$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/ryzen_smu/ryzen_smu.ko
      if [ ! -e "$ko.cer" ]; then
        chmod u+w "$ko"
        ${lib.getExe pkgs.buildPackages.kmodigest} "$ko"
        chmod 444 "$ko" "$ko.cer"
      fi
    '';
  });

  coMagnitude = 25;
  coall = 1048576 - coMagnitude; # 0x100000 - coMagnitude

  ryzenadjBin = "${pkgs.ryzenadj}/bin/ryzenadj";
in
{
  # Same as hardware.cpu.amd.ryzen-smu.enable, but with the signed package.
  boot.kernelModules = [ "ryzen-smu" ];
  boot.extraModulePackages = [ ryzenSmu ];

  environment.systemPackages = with pkgs; [
    #mprime
    ryzenadj
    ryzenSmu
  ];

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