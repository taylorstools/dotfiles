{ writeShellApplication, curl, jq, nix }:

# `nix flake update` for a flake that has inputs on the home Forgejo server.
# When that server is out of reach (off the LAN and off Tailscale), a plain
# `nix flake update` fails outright on the first unreachable input. This
# updates every other input instead and leaves the Forgejo ones at the
# revision flake.lock already pins. Forgejo inputs are found from the lock
# file by URL, so new ones are covered without editing this script.
writeShellApplication {
  name = "flake-update";
  runtimeInputs = [ curl jq nix ];
  text = ''
    ForgejoUrl="http://git.lan:3000"

    if [ "$#" -ne 1 ]; then
      echo "usage: flake-update <flake-dir>" >&2
      exit 2
    fi

    FlakeDir="$1"
    LockFile="$FlakeDir/flake.lock"

    if curl --silent --max-time 5 --output /dev/null "$ForgejoUrl"; then
      exec nix flake update --flake "$FlakeDir"
    fi

    if [ ! -f "$LockFile" ]; then
      echo "$ForgejoUrl is unreachable and $LockFile does not exist to pin its inputs from." >&2
      exit 1
    fi

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

    LocalInputs=()
    RemoteInputs=()
    while read -r Name Kind; do
      [ -n "$Name" ] || continue
      if [ "$Kind" = "local" ]; then
        LocalInputs+=("$Name")
      else
        RemoteInputs+=("$Name")
      fi
    done <<< "$InputTable"

    if [ "''${#LocalInputs[@]}" -eq 0 ]; then
      exec nix flake update --flake "$FlakeDir"
    fi

    echo "$ForgejoUrl is unreachable; keeping these inputs at their locked revision: ''${LocalInputs[*]}"

    if [ "''${#RemoteInputs[@]}" -eq 0 ]; then
      exit 0
    fi

    exec nix flake update --flake "$FlakeDir" "''${RemoteInputs[@]}"
  '';
}
