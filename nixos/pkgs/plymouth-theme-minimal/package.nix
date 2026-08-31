{ lib
, runCommand
, librsvg
, themeName ? "minimal"

  # Plymouth script themes get no HiDPI scaling, so these are raw pixels.
  # The .script derives all of its layout from the rendered image dimensions,
  # so changing them here is enough; the script itself never needs editing.
  # Note the initrd often runs at a lower mode than the panel's native one,
  # so these read larger at boot than they would on the desktop.
, fieldWidth ? 420
, fieldHeight ? 76
  # Half the field height renders as a full pill. Written as a ratio rather
  # than a literal so it stays a pill if fieldHeight ever changes; SVG clamps
  # rx to half the (inset) height anyway, so anything larger looks identical.
, cornerRadius ? fieldHeight / 2
, borderWidth ? 3
, bulletSize ? 14
  # Padlock height; width follows from the glyph's aspect. It sits inside the
  # field, so keep it comfortably under fieldHeight.
, lockHeight ? 40
  # Spinner shown while the rest of boot happens. 12 frames are pre-rotated at
  # build time; the .script hard-codes that count, so change both together.
, spinnerSize ? 40
, spinnerFrames ? 12

, foreground ? "#e6e6e6"
, background ? "#000000"
}:

let
  # SVG strokes straddle the path, so inset by half the border to keep the
  # outline inside the rendered bitmap.
  inset = borderWidth / 2.0;

  # The nf-fa-lock outline, lifted verbatim from Font Awesome's "lock" glyph
  # (U+F023), which is the contour Nerd Fonts vendors under that name.
  # Embedding the path rather than rasterising text from a font file is
  # deliberate: a font that fails to load, or that lacks the codepoint, does
  # not raise an error. It silently renders .notdef boxes, which is exactly
  # how this theme first shipped a row of tofu where the padlock should be.
  # Font Awesome by Dave Gandy, SIL OFL 1.1.
  lockPath =
    "M320 768V960C320 1101 435 1216 576 1216C717 1216 832 1101 832 960V768Z"
    + "M1152 672C1152 725 1109 768 1056 768H1024V960C1024 1206 822 1408 576 "
    + "1408C330 1408 128 1206 128 960V768H96C43 768 0 725 0 672V96C0 43 43 0 "
    + "96 0H1056C1109 0 1152 43 1152 96Z";

  # Glyph em box, from the font's own metrics.
  lockUnitsW = 1152;
  lockUnitsH = 1408;
  lockWidth = (lockHeight * lockUnitsW + (lockUnitsH / 2)) / lockUnitsH;

  fieldSvg = builtins.toFile "field.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg"
         viewBox="0 0 ${toString fieldWidth} ${toString fieldHeight}">
      <rect x="${toString inset}" y="${toString inset}"
            width="${toString (fieldWidth - borderWidth)}"
            height="${toString (fieldHeight - borderWidth)}"
            rx="${toString cornerRadius}"
            fill="${background}" stroke="${foreground}"
            stroke-width="${toString borderWidth}"/>
    </svg>
  '';

  # Font outlines are Y-up, SVG is Y-down, hence the flip.
  lockSvg = builtins.toFile "lock.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg"
         viewBox="0 0 ${toString lockUnitsW} ${toString lockUnitsH}">
      <g transform="scale(1,-1) translate(0,-${toString lockUnitsH})">
        <path d="${lockPath}" fill="${foreground}"/>
      </g>
    </svg>
  '';

  # @ANGLE@ is substituted per frame in the builder.
  spinnerSvg = builtins.toFile "spinner.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
      <g transform="rotate(@ANGLE@ 24 24)">
        <circle cx="24" cy="24" r="19" fill="none" stroke="${foreground}"
                stroke-opacity="0.18" stroke-width="4"/>
        <circle cx="24" cy="24" r="19" fill="none" stroke="${foreground}"
                stroke-width="4" stroke-linecap="round"
                stroke-dasharray="33 87"/>
      </g>
    </svg>
  '';

  bulletSvg = builtins.toFile "bullet.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
      <circle cx="8" cy="8" r="6" fill="${foreground}"/>
    </svg>
  '';
in
runCommand "plymouth-theme-${themeName}"
  {
    nativeBuildInputs = [ librsvg ];

    meta = {
      description =
        "Minimal Plymouth theme: bordered passphrase field with an inset nf-fa-lock padlock";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    dir="$out/share/plymouth/themes/${themeName}"
    mkdir -p "$dir"

    rsvg-convert -w ${toString fieldWidth} -h ${toString fieldHeight} \
      ${fieldSvg} -o "$dir/field.png"
    rsvg-convert -w ${toString lockWidth} -h ${toString lockHeight} \
      ${lockSvg} -o "$dir/lock.png"
    rsvg-convert -w ${toString bulletSize} -h ${toString bulletSize} \
      ${bulletSvg} -o "$dir/bullet.png"

    frames=${toString spinnerFrames}
    i=0
    while [ "$i" -lt "$frames" ]; do
      angle=$(( i * 360 / frames ))
      sed "s/@ANGLE@/$angle/" ${spinnerSvg} > frame.svg
      rsvg-convert -w ${toString spinnerSize} -h ${toString spinnerSize} \
        frame.svg -o "$dir/$(printf 'spinner-%02d' "$i").png"
      i=$(( i + 1 ))
    done

    cp ${./minimal.script} "$dir/${themeName}.script"

    # NixOS copies the selected theme into the initrd and rewrites any
    # /nix/store/*/share/plymouth/themes prefix to the initrd path, so the
    # absolute store paths written here are patched automatically.
    {
      echo "[Plymouth Theme]"
      echo "Name=Minimal"
      echo "Description=Bordered passphrase field with an inset nf-fa-lock padlock, no prompt text"
      echo "ModuleName=script"
      echo ""
      echo "[script]"
      echo "ImageDir=$dir"
      echo "ScriptFile=$dir/${themeName}.script"
    } > "$dir/${themeName}.plymouth"
  ''
