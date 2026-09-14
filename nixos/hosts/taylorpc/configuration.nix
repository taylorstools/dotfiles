{ pkgs, ... }:

{
  imports = [
    ../../modules/components/asus-laptop.nix
    ../../modules/laptop.nix
    ./disko.nix
    ./hostid.nix
    ./luks-tpm-autounlock.nix
  ];

  networking.hostName = "taylorpc";

  myOptions = {
    nvidia.mode = "disabled";

    amd = {
      mode = "amdgpu";
      rocm.enable = true;
    };

    davinci.enable = true;

    howdy = {
      enable = true;
      # Stable by-path node for the IR sensor; /dev/videoN can move on reboot.
      devicePath = "/dev/video2";
      # The IR emitter pulses, so only every other frame is bright enough for
      # the detector to find anything in - half the wall clock buys no frames.
      timeout = 8;

      extraSettings = {
        # The enrolled models were encoded with both of these in force. The
        # detector's framing feeds the encoder, so changing either shifts every
        # match distance and means re-enrolling. Leave them be.
        core.use_cnn = true;
        video.max_height = 480;
      };
    };

    roland.enable = true;
  };
}