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
  version = "0.1.0-unstable-2026-01-03";

  src = fetchFromGitHub {
    owner = "oknozor";
    repo = "roland";
    rev = "78351b998528bd335947fb59ea3e10c331c33331";
    hash = "sha256-wQCxgd2UavxWHKY4C3dZG/pRrLxSTDRajVgsO2E9GQM=";
  };

  cargoHash = lib.fakeHash;

  # config.rs has a test that reads a config.toml which isn't in the repo
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libinput
    udev
  ];

  meta = {
    description = "Simple touch gesture recognizer for Linux";
    homepage = "https://github.com/oknozor/roland";
    license = lib.licenses.unfree; # no LICENSE file upstream
    mainProgram = "roland";
    platforms = lib.platforms.linux;
  };
}