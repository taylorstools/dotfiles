{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libinput,
  udev,
}:

rustPlatform.buildRustPackage {
  pname = "roland";
  version = "0.1.0-unstable-2026-07-16";

  src = fetchFromGitHub {
    owner = "oknozor";
    repo = "roland";
    rev = "<full-commit-sha>";
    hash = lib.fakeHash;
  };

  cargoHash = lib.fakeHash;

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook # only needed if input-sys regenerates bindings
  ];

  buildInputs = [
    libinput
    udev
  ];

  meta = {
    description = "Simple touch gesture recognizer for Linux";
    homepage = "https://github.com/oknozor/roland";
    license = lib.licenses.unfree; # repo has no LICENSE file — see note below
    mainProgram = "roland";
    platforms = lib.platforms.linux;
  };
}