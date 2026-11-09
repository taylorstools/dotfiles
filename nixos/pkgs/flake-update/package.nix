{ writeShellApplication, curl, git, gnugrep, gnused, coreutils, jq, nix }:

# `nix flake update` for this flake, with two differences:
#
# Forgejo inputs: when the home Forgejo server is out of reach (off the LAN
# and off Tailscale), a plain `nix flake update` fails outright on the first
# unreachable input. This updates every other input instead and leaves the
# Forgejo ones at the revision flake.lock already pins. Forgejo inputs are
# found from the lock file by URL, so new ones are covered without editing
# this script.
#
# Release inputs: the inputs in ReleaseInputs are locked to their newest
# release tag instead of their branch head. A flake input cannot say "latest
# tag" itself, but flake.lock only has to agree with flake.nix on the input's
# `original` (the plain github:owner/repo there), not on the revision; so
# `nix flake lock --override-input` can put the tag's commit in the lock, and
# rebuilds use it until the next run here. Upstream commits between releases
# then no longer change the input (whisrs gets commits almost daily, and each
# one was a ~15 minute rebuild).
writeShellApplication {
  name = "flake-update";
  runtimeInputs = [ curl git gnugrep gnused coreutils jq nix ];
  text = ''
    ForgejoUrl="http://git.lan:3000"

    # GitHub inputs locked to their newest vX.Y.Z tag rather than their
    # default branch. Pre-release tags (v1.0.0-rc1 and the like) are skipped.
    ReleaseInputs=(whisrs)

    if [ "$#" -ne 1 ]; then
      echo "usage: flake-update <flake-dir>" >&2
      exit 2
    fi

    FlakeDir="$1"
    LockFile="$FlakeDir/flake.lock"

    isReleaseInput() {
      local R
      for R in "''${ReleaseInputs[@]}"; do
        [ "$R" = "$1" ] && return 0
      done
      return 1
    }

    pinToRelease() {
      local Name=$1 Spec Tag
      Spec="$(jq -r --arg Name "$Name" '
        .nodes.root.inputs[$Name] as $Node
        | select($Node | type == "string")
        | .nodes[$Node].original
        | select(.type == "github")
        | "\(.owner)/\(.repo)"
      ' "$LockFile")"
      if [ -z "$Spec" ]; then
        echo "$Name is not a GitHub input in $LockFile; leaving it as locked." >&2
        return 0
      fi

      Tag="$(git ls-remote --tags --refs "https://github.com/$Spec" 2>/dev/null \
        | sed -n 's|.*refs/tags/||p' \
        | grep -E '^v?[0-9]+(\.[0-9]+)*$' \
        | sort -V | tail -n1 || true)"
      if [ -z "$Tag" ]; then
        echo "No release tag found for $Name ($Spec); keeping its locked revision." >&2
        return 0
      fi

      echo "$Name: newest release is $Tag"
      nix flake lock "$FlakeDir" --override-input "$Name" "github:$Spec/$Tag"
    }

    if [ ! -f "$LockFile" ]; then
      # Nothing to read input names from yet: lock everything from scratch,
      # then move the release inputs onto their tags.
      if ! curl --silent --max-time 5 --output /dev/null "$ForgejoUrl"; then
        echo "$ForgejoUrl is unreachable and $LockFile does not exist to pin its inputs from." >&2
        exit 1
      fi
      nix flake update --flake "$FlakeDir"
      for Name in "''${ReleaseInputs[@]}"; do
        pinToRelease "$Name"
      done
      exit 0
    fi

    ForgejoUp=1
    curl --silent --max-time 5 --output /dev/null "$ForgejoUrl" || ForgejoUp=0

    # Root inputs as "<name> <local|remote>". A root input that is a follows
    # path (an array, not a node name) is never fetched itself.
    InputTable="$(jq -r --arg Url "$ForgejoUrl" '
      .nodes as $Nodes
      | .nodes.root.inputs
      | to_entries[]
      | select(.value | type == "string")
      | "\(.key) \(if ($Nodes[.value].original.url // "") | startswith($Url)
                   then "local" else "remote" end)"
    ' "$LockFile")"

    UpdateInputs=()
    SkippedLocal=()
    while read -r Name Kind; do
      [ -n "$Name" ] || continue
      isReleaseInput "$Name" && continue
      if [ "$Kind" = "local" ] && [ "$ForgejoUp" -eq 0 ]; then
        SkippedLocal+=("$Name")
        continue
      fi
      UpdateInputs+=("$Name")
    done <<< "$InputTable"

    if [ "''${#SkippedLocal[@]}" -gt 0 ]; then
      echo "$ForgejoUrl is unreachable; keeping these inputs at their locked revision: ''${SkippedLocal[*]}"
    fi

    if [ "''${#UpdateInputs[@]}" -gt 0 ]; then
      nix flake update --flake "$FlakeDir" "''${UpdateInputs[@]}"
    fi

    for Name in "''${ReleaseInputs[@]}"; do
      pinToRelease "$Name"
    done
  '';
}
