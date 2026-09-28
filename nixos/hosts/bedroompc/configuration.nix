{ ... }:

{
  imports = [
    ../../modules/htpc.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "bedroompc";

  myOptions.intel.mode = "modern";

  # The Intel GOP hands the initrd native 3840x2160, where livingroompc's
  # nvidia box drops to 1920x1080 before the kernel starts. The splash bitmaps
  # are fixed pixel sizes, so matching livingroompc's apparent size takes
  # twice its scale (the htpc.nix default of 1.5).
  myOptions.htpc.splashScale = 3.0;
}