{ pkgs, ... }:

let
  tela = pkgs.tela-icon-theme;

  # Swaps in a custom Thunar icon without rebuilding the theme. An
  # overrideAttrs on tela-icon-theme changes its derivation, so the cached
  # build is never used and every nixpkgs bump rebuilt all 48 variants.
  #
  # Not a symlinkJoin: the variants reach the icon through relative symlinks
  # (Tela-grey-dark/scalable -> ../Tela-grey/scalable, whose
  # apps/thunar.svg -> ../../../Tela/scalable/apps/thunar.svg). A link to a
  # whole directory resolves those inside the original package and shows the
  # stock icon. So the path down to each scalable/apps is rebuilt here with
  # the relative links copied as they are (they then resolve inside $out),
  # and everything else is an absolute link back to the cached theme. Only
  # the 16 real apps directories are copied; the other ~650k links are not.
  tela-custom = pkgs.runCommand "${tela.name}-custom-thunar"
    {
      inherit (tela) meta;
      preferLocalBuild = true;
    } ''
    shopt -s dotglob nullglob
    Src=${tela}/share/icons
    Dst=$out/share/icons

    # Recreates directory $1 (relative to $Src): relative links are copied
    # verbatim, anything else becomes an absolute link into the cached theme.
    # Entries named in the remaining arguments are skipped for the caller.
    shallow() {
      local Dir=$1 E Name; shift
      mkdir -p "$Dst/$Dir"
      for E in "$Src/$Dir"/*; do
        Name=''${E##*/}
        case " $* " in *" $Name "*) continue ;; esac
        if [ -L "$E" ]; then
          cp -P "$E" "$Dst/$Dir/$Name"
        else
          ln -s "$E" "$Dst/$Dir/$Name"
        fi
      done
    }

    mkdir -p $out/share
    for E in ${tela}/*; do [ "''${E##*/}" = share ] || ln -s "$E" $out/; done
    for E in ${tela}/share/*; do [ "''${E##*/}" = icons ] || ln -s "$E" $out/share/; done
    mkdir -p "$Dst"

    cd "$Src"
    for Theme in *; do
      if [ -L "$Theme" ] || [ ! -d "$Theme" ]; then
        cp -P "$Theme" "$Dst/$Theme" 2>/dev/null || ln -s "$Src/$Theme" "$Dst/$Theme"
      elif [ -d "$Theme/scalable/apps" ] && [ ! -L "$Theme/scalable" ]; then
        shallow "$Theme" scalable
        shallow "$Theme/scalable" apps
        cp -a "$Theme/scalable/apps" "$Dst/$Theme/scalable/apps"
      else
        shallow "$Theme"
      fi
    done

    Target="$Dst/Tela/scalable/apps/thunar.svg"
    test -e "$Target"
    chmod u+w "$Dst/Tela/scalable/apps"
    rm "$Target"
    cp ${./assets/thunar.svg} "$Target"
  '';
in
{
  environment.systemPackages = [ tela-custom ];
}
