{ lib
, stdenvNoCC
, python3
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

# User-tunable opacity constants — patched into dim-overlay.py at build time.
, opacityStep    ? 0.10
, opacityMin     ? 0.01
, opacityMax     ? 0.99
, opacityDefault ? 0.50
}:

let
  pyEnv = python3.withPackages (ps: with ps; [ pygobject3 pycairo ]);

  # Packages whose typelibs and shared libraries we need at runtime.
  # We scan every output of every package because nixpkgs sometimes splits
  # typelibs across `out` / `dev` / `devdoc`.
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
  pname   = "dim-overlay";
  version = "1.0.0";

  src = ./src;

  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/dim-overlay

    # Copy + patch the Python source with the configured opacity constants.
    install -m 644 dim-overlay.py $out/share/dim-overlay/dim-overlay.py
    substituteInPlace $out/share/dim-overlay/dim-overlay.py \
      --replace "OPACITY_STEP = 0.05" "OPACITY_STEP = ${toString opacityStep}" \
      --replace "OPACITY_MIN  = 0.05" "OPACITY_MIN  = ${toString opacityMin}" \
      --replace "OPACITY_MAX  = 0.95" "OPACITY_MAX  = ${toString opacityMax}" \
      --replace "OPACITY_DEF  = 0.40" "OPACITY_DEF  = ${toString opacityDefault}"

    # The actual python launcher with all GTK/typelib paths baked in.
    cat > $out/bin/dim-overlay <<EOF
    #!${stdenvNoCC.shell}
    export GI_TYPELIB_PATH="${giTypelibPath}\''${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${giLibraryPath}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    export GDK_BACKEND="\''${GDK_BACKEND:-wayland}"
    exec ${pyEnv}/bin/python $out/share/dim-overlay/dim-overlay.py "\$@"
    EOF
    chmod +x $out/bin/dim-overlay

    # Control scripts.  Each has its absolute path to dim-overlay baked in
    # via @DIM_OVERLAY@, and the python source path baked in via @PY_FILE@.
    for src in dim-overlay-on dim-overlay-undim dim-overlay-off; do
      install -m 755 "$src" "$out/bin/$src"
      substituteInPlace "$out/bin/$src" \
        --replace "@DIM_OVERLAY@" "$out/bin/dim-overlay" \
        --replace "@PY_FILE@" "$out/share/dim-overlay/dim-overlay.py"
    done

    runHook postInstall
  '';

  meta = with lib; {
    description = "Wayland layer-shell screen dimmer (below hardware minimum)";
    platforms   = platforms.linux;
    license     = licenses.mit;
    mainProgram = "dim-overlay";
  };
}
