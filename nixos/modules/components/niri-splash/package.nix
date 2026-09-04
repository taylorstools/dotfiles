{ lib
, stdenvNoCC
, python3
, xorg
, gtk4
, gtk4-layer-shell
, gobject-introspection
, glib
, graphene
, pango
, gdk-pixbuf
, harfbuzz
, cairo
, atk
, at-spi2-core
}:

# The splash program plus the transparent cursor theme it points niri at.
# Everything configurable is a command-line flag, set by default.nix.

let
  pyEnv = python3.withPackages (ps: with ps; [ pygobject3 pycairo ]);

  giPackages = [
    gtk4 gtk4-layer-shell gobject-introspection glib
    graphene pango gdk-pixbuf harfbuzz cairo atk at-spi2-core
  ];
  outputsOf = pkg: if pkg ? outputs then pkg.outputs else [ "out" ];
  allOutputPaths = suffix: pkg:
    map (o: "${pkg.${o}}${suffix}") (outputsOf pkg);
  giTypelibPath = lib.concatStringsSep ":"
    (lib.concatMap (allOutputPaths "/lib/girepository-1.0") giPackages);
  giLibraryPath = lib.concatStringsSep ":"
    (lib.concatMap (allOutputPaths "/lib") giPackages);
in
stdenvNoCC.mkDerivation {
  pname   = "niri-splash";
  version = "2.0.0";

  src = ./src;

  dontConfigure = true;
  dontBuild     = true;

  nativeBuildInputs = [ xorg.xcursorgen ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/niri-splash

    # A cursor theme whose every shape is a transparent 32x32 pixel. niri is
    # pointed at it from login until the splash lifts, so no cursor is drawn
    # on the empty screen before the shell exists.
    ${python3}/bin/python3 - <<'PNG'
    import struct, zlib
    w = h = 32
    raw = b"".join(b"\x00" + b"\x00" * (w * 4) for _ in range(h))
    def chunk(t, d):
        return (struct.pack(">I", len(d)) + t + d
                + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff))
    open("blank.png", "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    PNG
    theme=$out/share/icons/niri-splash-blank
    mkdir -p $theme/cursors
    echo "32 0 0 blank.png" > blank.cfg
    xcursorgen blank.cfg $theme/cursors/default
    for name in left_ptr arrow pointer top_left_arrow text xterm ibeam \
                hand hand1 hand2 pointing_hand grab grabbing openhand \
                closedhand watch wait progress left_ptr_watch half-busy \
                crosshair cross move fleur all-scroll not-allowed \
                col-resize row-resize ew-resize ns-resize nesw-resize \
                nwse-resize n-resize s-resize e-resize w-resize \
                ne-resize nw-resize se-resize sw-resize help question_arrow; do
      ln -s default $theme/cursors/$name
    done
    printf '[Icon Theme]\nName=niri-splash-blank\n' > $theme/index.theme

    install -m 644 niri-splash.py $out/share/niri-splash/niri-splash.py

    # Software rendering, no GL/Vulkan probing, no settings portal, no
    # accessibility bus: each of those was measured as hundreds of
    # milliseconds of cold-boot startup that a splash has no use for.
    cat > $out/bin/niri-splash <<EOF
    #!${stdenvNoCC.shell}
    export GI_TYPELIB_PATH="${giTypelibPath}\''${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${giLibraryPath}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    export GDK_BACKEND="\''${GDK_BACKEND:-wayland}"
    export GSK_RENDERER="\''${GSK_RENDERER:-cairo}"
    export GDK_DISABLE="\''${GDK_DISABLE:-gl,vulkan}"
    export GDK_DEBUG="\''${GDK_DEBUG:-no-portals,default-settings}"
    export GTK_A11Y="\''${GTK_A11Y:-none}"
    exec ${pyEnv}/bin/python $out/share/niri-splash/niri-splash.py "\$@"
    EOF
    chmod +x $out/bin/niri-splash

    runHook postInstall
  '';

  meta = with lib; {
    description = "Layer-shell startup splash for niri, held until the shell is on screen";
    platforms   = platforms.linux;
    license     = licenses.mit;
    mainProgram = "niri-splash";
  };
}
