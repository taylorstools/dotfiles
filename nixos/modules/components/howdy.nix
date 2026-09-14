{ config, lib, ... }:

let
  cfg = config.myOptions.howdy;
  username = config.myOptions.user.name;
in
{
  options.myOptions.howdy = {
    enable = lib.mkEnableOption "Howdy IR face authentication";

    devicePath = lib.mkOption {
      type = lib.types.str;
      default = "/dev/video2";
      example = "/dev/v4l/by-path/pci-0000:c4:00.4-usb-0:2:1.0-video-index2";
      description = ''
        v4l2 node of the IR sensor, not the RGB one. Bare /dev/videoN numbers
        are assigned in probe order and can move between boots once more than
        one capture device is in play, so a /dev/v4l/by-path/... path is the
        one to put here. `ls -l /dev/v4l/by-path/` maps them.
      '';
    };

    certainty = lib.mkOption {
      type = lib.types.float;
      default = 3.5;
      description = ''
        Match threshold, where lower is stricter. 3.5 is upstream's default.
        Drop it toward 2.5 if something that is not your face gets in; raise it
        if your own face is rejected in dim light.
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = ''
        Seconds to keep grabbing frames before giving up and handing the prompt
        back to pam_unix. Upstream's 4 is tight for a sensor that needs a moment
        to settle its exposure; 8 costs nothing when the match lands early,
        because Howdy returns on the first frame that matches.
      '';
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Turn on Howdy's own diagnostics: a notice while it looks, an end-of-run
        report, and a request to save a frame from every attempt. The notice is
        the useful part on NixOS: Howdy writes snapshots into its own install
        directory, which is a read-only /nix/store path here, so those silently
        never appear. To see what the sensor is actually handing OpenCV, grab
        frames yourself rather than trusting this to produce them.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = {
        core.use_cnn = true;
        video.exposure = 5;
      };
      description = ''
        Merged over everything this module computes, so it can reach any key in
        Howdy's config.ini without the module having to grow an option per
        knob. Useful during tuning, when which setting matters is exactly the
        thing in question.
      '';
    };

    services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "hyprlock" ];
      example = [ "hyprlock" "greetd" ];
      description = ''
        PAM services that accept a face in place of a password.

        Deliberately a short opt-in list. security.pam.howdy.enable defaults to
        services.howdy.enable, which puts pam_howdy in front of *every* PAM
        stack on the system - polkit included, where it currently cannot open
        the camera and takes the password fallback down with it, leaving no way
        to answer a polkit prompt at all. This module turns that global flag
        back off and enables only the services named here.

        sudo is not in the default list because security.sudo.wheelNeedsPassword
        is false in users.nix: wheel never authenticates, so pam_howdy would
        never run. Adding "su" here temporarily is worth remembering as a debug
        trick: hyprlock swallows everything pam_howdy prints, while `su - taylor`
        authenticates through PAM with the output attached to your terminal.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.howdy = {
      enable = true;

      # extraSettings goes on last so a hand-set key during tuning beats the
      # one this module computed for it.
      settings = lib.recursiveUpdate
        ({
          video = {
            device_path = cfg.devicePath;
            certainty = cfg.certainty;
            timeout = cfg.timeout;
          };
        }
        // lib.optionalAttrs cfg.debug {
          core.detection_notice = true;
          debug.end_report = true;
          snapshots.save_failed = true;
          snapshots.save_successful = true;
        })
        cfg.extraSettings;
    };

    security.pam.howdy.enable = false;

    security.pam.services = lib.genAttrs cfg.services (_: {
      howdy = {
        enable = true;

        # A face that matches authenticates and the stack stops there; a face
        # that does not falls through to pam_unix and the password prompt.
        # Upstream defaults this to "required", which inverts the intent: a
        # failed face check would then veto an otherwise correct password.
        control = "sufficient";
      };
    });

    # hyprlock runs as the user, so pam_howdy opens the camera as the user too
    # and needs group access to it. sudo would not, but the lock screen is the
    # whole point here.
    users.users.${username}.extraGroups = [ "video" ];
  };
}
