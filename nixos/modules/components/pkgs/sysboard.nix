{
  lib,
  stdenv,
  src,
  pkg-config,
  wayland-scanner,
  wayland,
  gtkmm4,
  gtk4-layer-shell,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sysboard";
  version =
    let
      d = src.lastModifiedDate or "00000000";
    in
    "0-unstable-${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";

  inherit src;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    gtkmm4
    gtk4-layer-shell
  ];

  # 1) Point the dlopen at the real lib path instead of a bare soname.
  # 2) Stub git_info.hpp so the Makefile's git-dependent target is skipped.
  postPatch = ''
    substituteInPlace src/main.cpp \
      --replace-fail '"libsysboard.so"' '"${placeholder "out"}/lib/libsysboard.so"'
    printf '#define GIT_COMMIT_MESSAGE "nixpkgs"\n#define GIT_COMMIT_DATE "${finalAttrs.version}"\n' \
      > src/git_info.hpp
  '';

  installFlags = [ "PREFIX=$(out)" ];

  meta = {
    homepage = "https://github.com/System64fumo/sysboard";
    description = "Simple GTK4 on-screen keyboard for Wayland";
    license = lib.licenses.mit; # confirm against the repo's LICENSE
    platforms = lib.platforms.linux;
    mainProgram = "sysboard";
  };
})