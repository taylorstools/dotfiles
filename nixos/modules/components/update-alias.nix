{ pkgs, ... }:

let
  update-alias = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = with pkgs; [ coreutils diffutils git gum nix nixos-rebuild ];
    text = ''
      set -euo pipefail

      DOTFILES="''${DOTFILES:-$HOME/.dotfiles}"
      HOST="$(hostname)"
      HOST_DIR="$DOTFILES/nixos/hosts/$HOST"
      ETC_NIXOS="/etc/nixos"

      # Per-host source-of-truth files synced from /etc/nixos before rebuild.
      SYNC_FILES=(
        hardware-configuration.nix
        hostid.nix
        disko.nix
        luks-tpm-autounlock.nix
      )

      if [ ! -d "$HOST_DIR" ]; then
        gum log --level error "Host directory $HOST_DIR does not exist!"
        exit 1
      fi

      # Discard local lock churn so the pull is always clean; drop the file
      # entirely when it is not in HEAD, so an incoming add applies.
      git -C "$DOTFILES" reset -q -- nixos/flake.lock || true
      git -C "$DOTFILES" checkout HEAD -- nixos/flake.lock 2>/dev/null \
        || rm -f "$DOTFILES/nixos/flake.lock"

      gum log --level info "Pulling latest dotfiles..."
      git -C "$DOTFILES" pull --rebase --autostash

      gum log --level info "Syncing per-host files from $ETC_NIXOS -> dotfiles..."
      for f in "''${SYNC_FILES[@]}"; do
        SRC="$ETC_NIXOS/$f"
        DST="$HOST_DIR/$f"
        if [ ! -f "$SRC" ]; then
          gum log --level warn "  $SRC not found, skipping"
          continue
        fi
        if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
          continue
        fi
        gum log --level info "  $SRC -> $DST"
        cp -f "$SRC" "$DST"
        git -C "$DOTFILES" add -f "nixos/hosts/$HOST/$f"
      done

      gum log --level info "Updating flake..."
      nix flake update --flake "$DOTFILES/nixos"

      gum log --level info "Rebuilding system configuration..."
      sudo nixos-rebuild switch --flake "$DOTFILES/nixos#$HOST"
    '';
  };
in
{
  environment.systemPackages = [ update-alias ];
}