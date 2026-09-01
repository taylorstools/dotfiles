{ lib
, runCommand
, librsvg
, gawk
, themeName ? "minimal"

  # Every dimension below is in "design units". They are multiplied by uiScale
  # and rasterised at exactly that size by rsvg-convert, which antialiases.
  # Nothing is resized at runtime: Plymouth's Image.Scale() does not
  # antialias, and putting a curved border through it is what made the pill's
  # corners look jagged.
  #
  # uiScale is therefore the single knob for "the whole prompt is too big or
  # too small", and it costs nothing: it changes the size rsvg rasterises at,
  # not the size of a finished bitmap, so any value stays crisp.
  #
  # The defaults below are sized for taylorpc's initrd framebuffer, which is
  # 1440x900 -- half the panel's native 2880x1800, since simpledrm comes up on
  # the firmware's GOP mode rather than the one amdgpu later sets. Tune
  # against a real boot, not a mockup.
, uiScale ? 1.0

, fieldWidth ? 230
, fieldHeight ? 42
  # Half the field height renders as a full pill. Written as a ratio so it
  # stays a pill if fieldHeight changes; SVG clamps rx to half the (inset)
  # height anyway, so anything larger looks identical.
, cornerRadius ? fieldHeight / 2
, borderWidth ? 2
, bulletSize ? 12
  # Centre-to-centre dot spacing as a multiple of dot size. Lower it and the
  # dots read bolder without growing; raise it and they read as a thin trail.
, bulletSpacing ? 1.5
  # Padlock height; width follows from the glyph's aspect. It sits inside the
  # field, so keep it comfortably under fieldHeight.
, lockHeight ? 22
  # The padlock's ink is bottom-heavy -- the solid body outweighs the thin
  # shackle, putting its centre of mass 10.1% of the glyph height below the
  # geometric centre. Centred by geometry it reads as sitting low, but
  # correcting by the full 0.101 overshoots into a visible 6px/10px gap, so
  # this is half of it: 7px above, 9px below. Rather than
  # offset it in the script, the glyph is rendered into a viewBox padded at the
  # bottom, so the bitmap's geometric centre already is the optical centre and
  # plain centring does the right thing. Set to 0 for true geometric centring.
, lockOpticalShift ? 0.05

  # Spinner shown while the rest of boot happens: a row of dots that brighten
  # and swell in sequence, echoing the passphrase dots. spinnerWidth is the
  # width of the whole row, not of one dot -- it wants to be a decent fraction
  # of fieldWidth or the spinner reads as a speck on its own in the middle of
  # a black screen. Frames are pre-rendered at build time and injected into
  # the script, so the count here is the only place it is written down.
  # Cycle length is spinnerFrames * spinnerTicks / 50 seconds.
  # spinnerPhase is the lag between adjacent dots in radians: 2*pi/dots reads
  # as one dot at a time, smaller values as a gentle travelling wave.
, spinnerWidth ? 74
, spinnerFrames ? 18
, spinnerTicks ? 4
, spinnerDots ? 3
, spinnerDotMin ? 3.2
, spinnerDotMax ? 5.0
, spinnerFadeMin ? 0.25
, spinnerPhase ? 0.7

, foreground ? "#e6e6e6"
, background ? "#000000"
  # Border colour after a rejected passphrase. Reverts to foreground as soon
  # as you start typing again.
, errorColour ? "#e05a52"

  # Refresh ticks to hold the field on screen after a passphrase is submitted,
  # before giving up and switching to the spinner. Purely cosmetic: rejection
  # is detected by call sequence, not by this timer, so getting it wrong costs
  # nothing but when the spinner appears on a correct passphrase.
  #
  # In ticks, not seconds, because the script has no clock. The pulse period
  # is the honest way to measure the tick rate -- it is pure tick count -- and
  # it puts refresh() at roughly the documented 50/sec. So 150 is about three
  # seconds. (An earlier 500 here came from timing a spinner flash, which was
  # really measuring how long the rejection took, not how long the grace ran.)
, verifyGraceTicks ? 150

  # While a passphrase is being checked, the whole prompt -- border, padlock
  # and the dots you typed -- pulses. pulseSteps is the half-cycle in refresh
  # ticks, so a full breath is 2 * pulseSteps / rate seconds. At ~50/sec, 32
  # gives about 1.3 seconds. Halve it to double the speed. pulseMin is how far
  # it dims.
, pulseSteps ? 32
, pulseMin ? 0.35
}:

let
  # Design units -> output pixels, rounded.
  px = v: toString (builtins.floor (v * uiScale + 0.5));

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

  # Transparent padding below the glyph, twice the correction so the shift
  # lands on the midpoint.
  lockPadUnits = builtins.floor (2.0 * lockOpticalShift * lockUnitsH + 0.5);
  lockBoxH = lockUnitsH + lockPadUnits;
  lockRenderH = (lockHeight * lockBoxH + (lockUnitsH / 2)) / lockUnitsH;

  mkFieldSvg = name: stroke: builtins.toFile name ''
    <svg xmlns="http://www.w3.org/2000/svg"
         viewBox="0 0 ${toString fieldWidth} ${toString fieldHeight}">
      <rect x="${toString inset}" y="${toString inset}"
            width="${toString (fieldWidth - borderWidth)}"
            height="${toString (fieldHeight - borderWidth)}"
            rx="${toString cornerRadius}"
            fill="${background}" stroke="${stroke}"
            stroke-width="${toString borderWidth}"/>
    </svg>
  '';

  fieldSvg = mkFieldSvg "field.svg" foreground;
  fieldErrorSvg = mkFieldSvg "field-error.svg" errorColour;

  # Font outlines are Y-up, SVG is Y-down, hence the flip.
  mkLockSvg = name: fill: builtins.toFile name ''
    <svg xmlns="http://www.w3.org/2000/svg"
         viewBox="0 0 ${toString lockUnitsW} ${toString lockBoxH}">
      <g transform="scale(1,-1) translate(0,-${toString lockUnitsH})">
        <path d="${lockPath}" fill="${fill}"/>
      </g>
    </svg>
  '';

  lockSvg = mkLockSvg "lock.svg" foreground;
  lockErrorSvg = mkLockSvg "lock-error.svg" errorColour;

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

    rsvg-convert -w ${px fieldWidth} -h ${px fieldHeight} \
      ${fieldSvg} -o "$dir/field.png"
    rsvg-convert -w ${px fieldWidth} -h ${px fieldHeight} \
      ${fieldErrorSvg} -o "$dir/field-error.png"
    rsvg-convert -w ${px lockWidth} -h ${px lockRenderH} \
      ${lockSvg} -o "$dir/lock.png"
    rsvg-convert -w ${px lockWidth} -h ${px lockRenderH} \
      ${lockErrorSvg} -o "$dir/lock-error.png"
    rsvg-convert -w ${px bulletSize} -h ${px bulletSize} \
      ${bulletSvg} -o "$dir/bullet.png"

    # Dots are laid out on a 48x16 viewBox, centred as a row. Each frame is a
    # phase step; awk is here only because the shell has no sin().
    frames=${toString spinnerFrames}
    : > spinner-lines.txt
    i=0
    while [ "$i" -lt "$frames" ]; do
      printf 'spinner.frames[%d] = Image("spinner-%02d.png");\n' "$i" "$i" \
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
      rsvg-convert -w ${px spinnerWidth} -h ${px (spinnerWidth / 3)} \
        frame.svg -o "$dir/$(printf 'spinner-%02d' "$i").png"
      i=$(( i + 1 ))
    done

    sed -e "s/@BULLET_SPACING@/${toString bulletSpacing}/g" \
        -e "s/@VERIFY_GRACE@/${toString verifyGraceTicks}/g" \
        -e "s/@PULSE_STEPS@/${toString pulseSteps}/g" \
        -e "s/@PULSE_MIN@/${toString pulseMin}/g" \
        -e "s/@SPINNER_COUNT@/${toString spinnerFrames}/g" \
        -e "s/@SPINNER_TICKS@/${toString spinnerTicks}/g" \
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
