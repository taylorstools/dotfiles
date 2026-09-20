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

      # pam_howdy races a face check against its own password prompt, and
      # anything typed while the face check is still running is eaten by the
      # losing thread. Nothing in the PAM stack can separate them, so the only
      # lever is how long that window stays open: a match that is going to land
      # lands in the first second or two, and 8s was for debugging.
      timeout = 3;

      extraSettings = {
        # HOG, not the CNN detector: the CNN costs an extra 100MB model load
        # plus most of a second per frame, and it was only ever an experiment
        # from chasing a failure that turned out to be the match threshold.
        core.use_cnn = false;

        # Above upstream's 320 so the detector has enough face to work with at
        # lock-screen distance. Detection framing feeds the encoder, so this
        # and use_cnn above both invalidate enrolled models when changed -
        # re-enroll after touching either.
        video.max_height = 480;
      };
    };

    roland.enable = true;
  };
}