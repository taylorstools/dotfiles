{ lib
, runCommand
, librsvg
, imagemagick
, nerd-fonts
, themeName ? "minimal"

  # Plymouth script themes get no HiDPI scaling, so these are raw pixels,
  # sized for the PX13's 2880x1800 panel. The .script derives all of its
  # layout from the rendered image dimensions, so changing them here is
  # enough -- the script itself never needs editing.
, fieldWidth ? 420
, fieldHeight ? 76
  # Half the field height renders as a full pill. Written as a ratio rather
  # than a literal so it stays a pill if fieldHeight ever changes; SVG clamps
  # rx to half the (inset) height anyway, so anything larger looks identical.
, cornerRadius ? fieldHeight / 2
, borderWidth ? 3
, bulletSize ? 14

  # The padlock is the nf-fa-lock glyph (Font Awesome's lock, U+F023 in the
  # Nerd Fonts private use area). It is taller than it is wide, so this sets
  # the rendered height; width follows from the glyph's own aspect ratio.
  # It sits inside the field, so keep it comfortably under fieldHeight.
, lockHeight ? 40
, glyphFont ? nerd-fonts.symbols-only
, glyphCodepoint ? "f023"

, foreground ? "#e6e6e6"
, background ? "#000000"
}:

let
  # SVG strokes straddle the path, so inset by half the border to keep the
  # outline inside the rendered bitmap.
  inset = borderWidth / 2.0;

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

  bulletSvg = builtins.toFile "bullet.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
      <circle cx="8" cy="8" r="6" fill="${foreground}"/>
    </svg>
  '';
in
runCommand "plymouth-theme-${themeName}"
  {
    nativeBuildInputs = [ librsvg imagemagick ];

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
    rsvg-convert -w ${toString bulletSize} -h ${toString bulletSize} \
      ${bulletSvg} -o "$dir/bullet.png"

    # Rasterise the padlock straight out of the Nerd Font. -trim strips the
    # glyph's side bearings so the bitmap is exactly the mark, which lets the
    # .script position it from its own dimensions.
    font=$(find ${glyphFont}/share/fonts -type f \
      \( -name '*.ttf' -o -name '*.otf' \) | sort | head -n1)
    if [ -z "$font" ]; then
      echo "no font file found in ${glyphFont}" >&2
      exit 1
    fi
    echo "glyph font: $font"

    glyph=$(printf '\u${glyphCodepoint}')
    magick -background none -fill "${foreground}" -font "$font" \
      -pointsize 512 "label:$glyph" \
      -trim +repage -resize "x${toString lockHeight}" \
      "$dir/lock.png"

    # A missing glyph renders as nothing at all rather than failing, so check.
    dims=$(magick identify -format '%wx%h' "$dir/lock.png")
    echo "lock glyph: $dims"
    case "$dims" in
      [0-3]x*|*x[0-3])
        echo "glyph U+${glyphCodepoint} rendered empty; wrong font or codepoint" >&2
        exit 1
        ;;
    esac

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
