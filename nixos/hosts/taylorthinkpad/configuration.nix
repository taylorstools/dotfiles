{ ... }:

{
  imports = [
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "taylorthinkpad";

  myOptions = {
    # ThinkPad x210AI: an Ultra 9 185H board in an X201 chassis. Meteor Lake
    # Arc graphics only, so "modern" (iHD + vpl-gpu-rt) is the right tier and
    # there is no discrete GPU to configure -- nvidia.mode and amd.mode stay at
    # their "disabled"/"none" defaults.
    intel.mode = "modern";

    # Deliberately not set here, unlike taylorpc:
    #   davinci.enable - the module asserts a CUDA or ROCm backend, and an
    #                    Intel iGPU is not a supported Resolve target on Linux.
    #   howdy.enable   - no IR sensor in this chassis.
    #   roland.enable  - no touchscreen.
    # Nothing from modules/components/asus-laptop.nix is imported either:
    # asusd, supergfxd, the asus keyboard tool, the kbd-backlight shim and the
    # ryzenadj undervolt are all PX13 hardware.
  };
}
