{ lib
, runCommand
, librsvg
, gawk
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
  # Spinner shown while the rest of boot happens: a row of dots that brighten
  # and swell in sequence, echoing the passphrase dots. Frames are pre-rendered
  # at build time; the .script hard-codes the count, so change both together.
  # spinnerPhase is the lag between adjacent dots in radians: 2*pi/dots reads
  # as one dot at a time, smaller values as a gentle travelling wave.
, spinnerSize ? 40
, spinnerFrames ? 18
, spinnerTicks ? 4
, spinnerDots ? 3
, spinnerDotMin ? 3.2
, spinnerDotMax ? 5.0
, spinnerFadeMin ? 0.25
, spinnerPhase ? 0.7

  # How wide the field should be as a fraction of the screen, whatever mode
  # the initrd comes up in. The sizes above are art dimensions, not final
  # ones: the .script scales everything to hit this. Lower it if the prompt
  # still reads large.
, fieldScreenFraction ? 0.16

  # Art is rendered this many times larger than nominal so the runtime scale
  # is always a downscale, which resamples far better than blowing up.
, supersample ? 2

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

  bulletSvg = builtins.toFile "bullet.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
      <circle cx="8" cy="8" r="6" fill="${foreground}"/>
    </svg>
  '';
in
runCommand "plymouth-theme-${themeName}"
  {
    nativeBuildInputs = [ librsvg gawk ];

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

    rsvg-convert -w ${toString (fieldWidth * supersample)} -h ${toString (fieldHeight * supersample)} \
      ${fieldSvg} -o "$dir/field.png"
    rsvg-convert -w ${toString (lockWidth * supersample)} -h ${toString (lockHeight * supersample)} \
      ${lockSvg} -o "$dir/lock.png"
    rsvg-convert -w ${toString (bulletSize * supersample)} -h ${toString (bulletSize * supersample)} \
      ${bulletSvg} -o "$dir/bullet.png"

    # Dots are laid out on a 48x16 viewBox, centred as a row. Each frame is a
    # phase step; awk is here only because the shell has no sin().
    frames=${toString spinnerFrames}
    : > spinner-lines.txt
    i=0
    while [ "$i" -lt "$frames" ]; do
      printf 'spinner.raw[%d] = Image("spinner-%02d.png");\n' "$i" "$i" \
        >> spinner-lines.txt
      awk -v i="$i" -v n="$frames" \
          -v dots=${toString spinnerDots} \
          -v rmin=${toString spinnerDotMin} -v rmax=${toString spinnerDotMax} \
          -v omin=${toString spinnerFadeMin} -v phase=${toString spinnerPhase} '
        BEGIN {
          pi = 3.141592653589793;
          start = 24 - (dots - 1) * 7;
          printf "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 48 16\">";
          for (k = 0; k < dots; k++) {
            t = 0.5 + 0.5 * sin(i / n * 2 * pi - k * phase);
            r = rmin + (rmax - rmin) * t;
            o = omin + (1 - omin) * t;
            printf "<circle cx=\"%g\" cy=\"8\" r=\"%.2f\" fill=\"${foreground}\" fill-opacity=\"%.2f\"/>", start + k * 14, r, o;
          }
          printf "</svg>";
        }' > frame.svg
      rsvg-convert -w ${toString (spinnerSize * supersample)} \
        -h ${toString (spinnerSize * supersample / 3)} \
        frame.svg -o "$dir/$(printf 'spinner-%02d' "$i").png"
      i=$(( i + 1 ))
    done

    sed -e "s/@FIELD_FRACTION@/${toString fieldScreenFraction}/" \
        -e "s/@SPINNER_COUNT@/${toString spinnerFrames}/" \
        -e "s/@SPINNER_TICKS@/${toString spinnerTicks}/" \
        -e "/@SPINNER_FRAMES@/r spinner-lines.txt" \
        -e "/@SPINNER_FRAMES@/d" \
        ${./minimal.script} > "$dir/${themeName}.script"

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
