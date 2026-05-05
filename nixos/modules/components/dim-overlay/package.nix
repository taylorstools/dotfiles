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

, opacityStep              ? 0.05
, opacityFineStep          ? 0.02
, opacityFineStepThreshold ? 0.90
, opacityMin               ? 0.50
, opacityMax               ? 1.00
, opacityDefault           ? 0.50
}:

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
  pname   = "dim-overlay";
  version = "1.1.0";

  src = ./src;

  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/dim-overlay

    install -m 644 dim-overlay.py $out/share/dim-overlay/dim-overlay.py
    substituteInPlace $out/share/dim-overlay/dim-overlay.py \
      --replace "OPACITY_STEP           = 0.05" "OPACITY_STEP           = ${toString opacityStep}" \
      --replace "OPACITY_FINE_STEP      = 0.02" "OPACITY_FINE_STEP      = ${toString opacityFineStep}" \
      --replace "OPACITY_FINE_THRESHOLD = 0.90" "OPACITY_FINE_THRESHOLD = ${toString opacityFineStepThreshold}" \
      --replace "OPACITY_MIN            = 0.05" "OPACITY_MIN            = ${toString opacityMin}" \
      --replace "OPACITY_MAX            = 0.95" "OPACITY_MAX            = ${toString opacityMax}" \
      --replace "OPACITY_DEF            = 0.40" "OPACITY_DEF            = ${toString opacityDefault}"

    cat > $out/bin/dim-overlay <<EOF
    #!${stdenvNoCC.shell}
    export GI_TYPELIB_PATH="${giTypelibPath}\''${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"
    export LD_LIBRARY_PATH="${giLibraryPath}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    export GDK_BACKEND="\''${GDK_BACKEND:-wayland}"
    exec ${pyEnv}/bin/python $out/share/dim-overlay/dim-overlay.py "\$@"
    EOF
    chmod +x $out/bin/dim-overlay

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
