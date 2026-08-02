{
  lib,
  stdenvNoCC,
  sassc,
  gtk3,
  gnome-themes-extra,
  src,
  colorVariants ? [ "dark" ],
  themeVariants ? [ "default" ],
  tweaks ? [ ],
}:

stdenvNoCC.mkDerivation {
  pname = "orchis-theme";
  version = src.shortRev or "unstable";

  inherit src;

  nativeBuildInputs = [ sassc ];
  buildInputs = [
    gtk3
    gnome-themes-extra
  ];

  postPatch = ''
    patchShebangs install.sh
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/themes

    name= HOME="$TMPDIR" ./install.sh \
      --dest $out/share/themes \
      --theme ${toString themeVariants} \
      --color ${toString colorVariants} \
      ${lib.optionalString (tweaks != [ ]) "--tweaks ${toString tweaks}"}

    runHook postInstall
  '';

  meta = {
    description = "Material Design theme for GNOME/GTK based desktop environments";
    homepage = "https://github.com/vinceliuice/Orchis-theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}