{ stdenv, linuxPackages, fetchFromGitHub }:

stdenv.mkDerivation {
  name = "hp-audio-fix";

  src = fetchFromGitHub {
    owner = "xoocoon";
    repo = "hp-15-ew0xxx-snd-fix";
    rev = "main";
    sha256 = "sha256-V6Qkt7yGzHtgg0oGaBjrkOTAm9J9QYM9buqdnkf9NL4=";
  };

  buildInputs = linuxPackages.kernel.moduleBuildDependencies;

  buildPhase = ''
    # You will need to adapt this:
    # extract + patch kernel module manually
    echo "Implement build logic here"
  '';

  installPhase = ''
    mkdir -p $out/lib/modules/${linuxPackages.kernel.modDirVersion}/extra
    # copy built module here
  '';
}