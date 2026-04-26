{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;

  pyEnv = pkgs.python3.withPackages (ps: with ps; [ pygobject3 pycairo ]);

  giPackages = with pkgs; [
    gtk4
    gtk4-layer-shell
    gobject-introspection
    glib
    graphene
    pango
    gdk-pixbuf
    harfbuzz
    cairo
    atk
    at-spi2-core
  ];

  # Some nixpkgs packages split typelibs across multiple outputs (out, dev,
  # devdoc, etc.).  lib.makeSearchPath only inspects the default output, so
  # we hand-roll a version that scans every output of every package.
  outputsOf = pkg: if pkg ? outputs then pkg.outputs else [ "out" ];
  allOutputPaths = suffix: pkg:
    map (o: "${pkg.${o}}${suffix}") (outputsOf pkg);

  giTypelibPath = lib.concatStringsSep ":"
    (lib.concatMap (allOutputPaths "/lib/girepository-1.0") giPackages);
  giLibraryPath = lib.concatStringsSep ":"
    (lib.concatMap (allOutputPaths "/lib") giPackages);
in
pkgs.writeShellScriptBin "dim-overlay-python" ''
  export GI_TYPELIB_PATH="${giTypelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
  export LD_LIBRARY_PATH="${giLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export GDK_BACKEND="''${GDK_BACKEND:-wayland}"
  exec ${pyEnv}/bin/python "$@"
''
