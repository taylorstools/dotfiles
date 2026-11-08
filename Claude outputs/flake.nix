{
  description = "A flake for DaVinci Resolve Studio with FFmpeg encoder plugin and patches";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # nixos-unstable commit carrying DaVinci Resolve Studio 21.1.1.
    # Pinned by commit so the ~3 GB Resolve download only happens when you bump this.
    nixpkgs-pinned.url = "github:NixOS/nixpkgs/55bfb4d7437bd4e09ab7cba58a43bd68eb310044";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-pinned,
    ...
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    pkgs-pinned = import nixpkgs-pinned {
      inherit system;
      config.allowUnfree = true;
    };

    ffmpeg-encoder-plugin = pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "ffmpeg-encoder-plugin";
      version = "1.4.0";
      env.NIX_CFLAGS_COMPILE = "-D__STDC_CONSTANT_MACROS";

      src = pkgs.fetchFromGitHub {
        owner = "EdvinNilsson";
        repo = "ffmpeg_encoder_plugin";
        rev = "v${finalAttrs.version}";
        hash = "sha256-q37cA1GR2+qPzrJVrAN9uOqEmQ6ehPrmZWt+v4W94OE=";
      };

      nativeBuildInputs = [pkgs.cmake];
      buildInputs = [
        pkgs.ffmpeg-full
        # 1.4.0 adds VAAPI and Vulkan hardware encoders (H.264 / H.265 / AV1)
        pkgs.libva
        pkgs.vulkan-headers
      ];

      installPhase = ''
        mkdir -p $out
        cp ffmpeg_encoder_plugin.dvcp $out/
      '';
    });

    davinci-resolve-studio-cracked = let
      davinci-patched = let
        # Should prevent useless rebuilds of the actual binary
        davinci-locked = pkgs-pinned.davinci-resolve-studio;
      in
        davinci-locked.davinci.overrideAttrs (old: {
        });
      # Give Resolve a single ALSA device that always exists so it doesn't hang
      # at startup. No `device` is set, so the pulse plugin follows PipeWire's
      # current default sink/source (and PipeWire moves the stream when the
      # default changes: speakers -> Bluetooth -> HDMI, etc.).
      # Note: ALSA_CONFIG_PATH replaces alsa.conf entirely, so only the PCMs
      # defined here exist inside the sandbox.
      davinciAlsaConfig = pkgs.writeText "davinci-alsa.conf" ''
        pcm.!default {
          type pulse
          hint {
            show on
            description "Default (PipeWire)"
          }
        }

        ctl.!default {
          type pulse
        }
      '';

      execName = davinci-patched.pname;

      # Extra programs bundled with Resolve; each re-enters the FHS env and execs its binary
      mkWrapper = name: bin:
        pkgs.writeShellScript name ''
          exec "$(dirname "$0")/${execName}" ${bin} "$@"
        '';
      wrappers = {
        "blackmagicraw-player" = "${davinci-patched}/BlackmagicRAWPlayer/BlackmagicRAWPlayer";
        "blackmagicraw-speedtest" = "${davinci-patched}/BlackmagicRAWSpeedTest/BlackmagicRAWSpeedTest";
        "davinci-control-panels-setup" = ''"${davinci-patched}/DaVinci Control Panels Setup/DaVinci Control Panels Setup"'';
        "davinci-fairlight-studio-utility" = ''"${davinci-patched}/Fairlight Studio Utility/Fairlight Studio Utility"'';
        "davinci-remote-monitor" = ''"${davinci-patched}/bin/DaVinci Remote Monitor"'';
      };
    in
      pkgs.buildFHSEnv {
        inherit (davinci-patched) pname version;

        targetPkgs = inner-pkgs:
          with inner-pkgs;
            [
              alsa-lib
              alsa-plugins
              libpulseaudio # runtime dep of the ALSA pulse plugin used by davinciAlsaConfig
              aprutil
              bzip2
              dbus
              expat
              fontconfig
              freetype
              glib
              libGL
              libGLU
              libarchive
              libcap
              librsvg
              libtool
              libuuid
              libxcrypt-legacy # provides libcrypt.so.1
              libxkbcommon
              nspr
              ocl-icd
              opencl-headers
              python3
              python3.pkgs.numpy
              libdrm # libdrm.so.2 needed by bundled Qt6 WebEngine (Control Panels Setup)
              libxkbfile # libxkbfile.so.1 needed by bundled Qt6 WebEngine (Control Panels Setup)
              krb5 # libgssapi_krb5.so.2 needed by bundled Qt6 (Control Panels Setup, Fairlight Studio Utility)
              nss # libsmime3.so needed by bundled Qt6 (Control Panels Setup)
              libxcb-cursor # needed by Qt6 xcb platform plugin (Fairlight Studio Utility)
              udev
              xdg-utils
              libice
              libsm
              libx11
              libxcomposite
              libxcursor
              libxdamage
              libxext
              libxfixes
              libxi
              libxinerama
              libxrandr
              libxrender
              libxt
              libxtst
              libxxf86vm
              libxcb
              libxcb-util
              libxcb-image
              libxcb-keysyms
              libxcb-render-util
              libxcb-wm
              xkeyboard-config
              zlib
            ]
            ++ [
              # mesa-good-pkg
              davinci-patched
            ];

        extraPreBwrapCmds = ''
          mkdir -p ~/.local/share/DaVinciResolve/Extras || exit 1
        '';

        extraBwrapArgs = [
          ''--bind "$HOME"/.local/share/DaVinciResolve/Extras /Extras''

          "--dir /IOPlugins/ffmpeg_encoder_plugin.dvcp.bundle/Contents/Linux-x86-64"

          "--ro-bind ${ffmpeg-encoder-plugin}/ffmpeg_encoder_plugin.dvcp /IOPlugins/ffmpeg_encoder_plugin.dvcp.bundle/Contents/Linux-x86-64/ffmpeg_encoder_plugin.dvcp"
        ];

        runScript = "${lib.getExe pkgs.bash} ${pkgs.writeText "davinci-wrapper" ''
          # Strip host Qt settings that crash Resolve's bundled Qt
          unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE QML2_IMPORT_PATH

          export ALSA_CONFIG_PATH="${davinciAlsaConfig}"
          export QT_XKB_CONFIG_ROOT="${pkgs.xkeyboard_config}/share/X11/xkb"
          # Use only Resolve's bundled plugins; don't append the host's QT_PLUGIN_PATH
          export QT_PLUGIN_PATH="${davinci-patched}/libs/plugins"
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib:/usr/lib32:${davinci-patched}/libs
          export QT_QPA_PLATFORM=xcb
          unset WAYLAND_DISPLAY

          # Bundled extras (Fairlight utility, RAW player, ...) re-enter here
          # with their binary as an argument
          if [ $# -gt 0 ]; then
            exec "$@"
          fi

          # Resolve's UI Display Scale (Preferences > User > UI Settings) is
          # applied by its bundled Qt and enlarges the pointer too: at 150% the
          # cursor is 1.5x its normal size. Divide XCURSOR_SIZE by the same
          # factor so the pointer matches the rest of the desktop. Only Resolve
          # itself reads this preference; the extras take the branch above.
          Scale="$(${pkgs.gnused}/bin/sed -n \
            's:.*<DisplayScale>\([0-9][0-9]*\)</DisplayScale>.*:\1:p' \
            "$HOME/.local/share/DaVinciResolve/configs/config.user.xml" 2>/dev/null \
            | ${pkgs.coreutils}/bin/head -n1)"
          Base="''${XCURSOR_SIZE:-24}"
          case "$Scale:$Base" in
            *[!0-9:]*|:*|*:) ;;
            *)
              if [ "$Scale" -gt 100 ]; then
                export XCURSOR_SIZE=$(( (Base * 100 + Scale / 2) / Scale ))
              fi
              ;;
          esac

          exec ${davinci-patched}/bin/resolve
        ''}";

        extraInstallCommands = ''
          # Desktop files
          mkdir -p $out/share/applications
          ln -s ${davinci-patched}/share/applications/*.desktop $out/share/applications/

          # Icons
          mkdir -p $out/share/icons/hicolor/{128x128,256x256}/apps
          ln -s ${davinci-patched}/graphics/DV_Resolve.png $out/share/icons/hicolor/128x128/apps/${execName}.png
          ln -s ${davinci-patched}/graphics/DV_Panels.png $out/share/icons/hicolor/128x128/apps/davinci-control-panels-setup.png
          ln -s ${davinci-patched}/graphics/Remote_Monitoring.png $out/share/icons/hicolor/128x128/apps/davinci-remote-monitor.png
          ln -s ${davinci-patched}/graphics/blackmagicraw-player_256x256_apps.png $out/share/icons/hicolor/256x256/apps/blackmagicraw-player.png
          ln -s ${davinci-patched}/graphics/blackmagicraw-speedtest_256x256_apps.png $out/share/icons/hicolor/256x256/apps/blackmagicraw-speedtest.png

          # Wrapper scripts for the bundled extra programs
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: bin: ''
              ln -s ${mkWrapper name bin} $out/bin/${name}
            '')
            wrappers
          )}

          # MIME type definitions for .drp, .braw, etc.
          mkdir -p $out/share/mime/packages
          ln -s ${davinci-patched}/share/resolve.xml $out/share/mime/packages/
          ln -s ${davinci-patched}/share/blackmagicraw.xml $out/share/mime/packages/

          # udev rules for Blackmagic hardware (picked up via services.udev.packages)
          mkdir -p $out/lib/udev/rules.d
          ln -s ${davinci-patched}/lib/udev/rules.d/*.rules $out/lib/udev/rules.d/
        '';

        passthru = {
          inherit davinci-patched ffmpeg-encoder-plugin;
        };

        meta = {
          description = "DaVinci Resolve Studio with the FFmpeg encoder plugin";
          license = lib.licenses.unfree;
          platforms = ["x86_64-linux"];
          mainProgram = execName;
        };
      };
  in {
    packages.${system} = {
      davinci-resolve-studio-cracked = davinci-resolve-studio-cracked;
      inherit ffmpeg-encoder-plugin;
      default = davinci-resolve-studio-cracked;
    };
  };
}
