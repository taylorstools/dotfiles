# `llm`: one command to get a chat prompt on the Ollama VM.
#
# It SSHes to the Proxmox host, shuts down every other running VM there,
# starts the LLM VM if it isn't already running, waits for it to come up, then
# opens an interactive `ollama run` session on it over SSH.
#
# Usage:
#   llm              # chat with the newest model in `ollama list` on the VM
#   llm qwen3:14b    # chat with a specific model
#   /bye or Ctrl+D   # leave the chat (the VM keeps running)
#
# Before the first run, create the credentials file. It is read by your user,
# not root, and must NOT go in git or the chezmoi tree:
#   sudo install -m 0600 -o taylor -g users /dev/null /etc/llm-chat.cred
# then open /etc/llm-chat.cred in an editor and add:
#   proxmox_password=ROOT_PASSWORD_ON_PROXMOX
#   llm_password=TAYLOR_PASSWORD_ON_THE_LLM_VM
# (An editor rather than `tee <<EOF`, which leaves the passwords in shell
# history.) Leave a line out, or skip the file entirely, and ssh falls back to
# keys or an interactive password prompt for that host.

{ config, lib, pkgs, ... }:

let
  cfg = config.myOptions.llmChat;

  # Runs on the Proxmox host as root. Args: target VM id, shutdown timeout.
  pveScript = pkgs.writeText "llm-chat-pve.sh" ''
    set -euo pipefail
    TargetId="$1"
    ShutdownTimeout="$2"

    if ! qm status "$TargetId" >/dev/null 2>&1; then
      echo "VM $TargetId doesn't exist on $(hostname)." >&2
      exit 1
    fi

    # qm list columns: VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID
    mapfile -t Others < <(qm list | awk -v Target="$TargetId" \
      'NR > 1 && $3 == "running" && $1 != Target { print $1 " " $2 }')

    for Entry in "''${Others[@]}"; do
      read -r Id Name <<< "$Entry"
      echo "Shutting down VM $Id ($Name)..."
      # Clean ACPI/guest-agent shutdown; blocks until the VM is off. Never
      # force it: a hard stop on a Windows guest mid-update is worse than
      # not getting a chat prompt.
      if ! qm shutdown "$Id" --timeout "$ShutdownTimeout"; then
        echo "VM $Id ($Name) didn't shut down within $ShutdownTimeout seconds." >&2
        echo "Check on it, or force it off on the host with: qm stop $Id" >&2
        exit 1
      fi
    done

    Status="$(qm status "$TargetId" | awk '{ print $2 }')"
    case "$Status" in
      running)
        echo "VM $TargetId is already running."
        ;;
      stopped)
        echo "Starting VM $TargetId..."
        qm start "$TargetId"
        ;;
      *)
        echo "VM $TargetId is in state '$Status'; leaving it alone." >&2
        exit 1
        ;;
    esac
  '';

  # Runs on the LLM VM as the login user. Arg: model name, or empty for the
  # newest one installed. Kept POSIX so it doesn't care what the login shell is.
  chatScript = pkgs.writeText "llm-chat-vm.sh" ''
    set -eu
    Model="''${1:-}"

    # Right after boot, sshd can be up a few seconds before ollama is.
    Tries=0
    until ollama list >/dev/null 2>&1; do
      Tries=$((Tries + 1))
      if [ "$Tries" -ge 60 ]; then
        echo "Ollama isn't answering on $(hostname). Check: systemctl status ollama" >&2
        exit 1
      fi
      sleep 1
    done

    if [ -z "$Model" ]; then
      Model="$(ollama list | awk 'NR == 2 { print $1 }')"
      if [ -z "$Model" ]; then
        echo "No models installed on $(hostname). Pull one with: ollama pull <model>" >&2
        exit 1
      fi
    fi

    echo "Chatting with $Model. Type /bye or press Ctrl+D to quit."
    exec ollama run "$Model"
  '';

  llm = pkgs.writeShellApplication {
    name = "llm";
    runtimeInputs = with pkgs; [ bash coreutils gum openssh sshpass ];
    text = ''
      # Config
      ProxmoxHost=${lib.escapeShellArg cfg.proxmox.host}
      ProxmoxUser=${lib.escapeShellArg cfg.proxmox.user}
      VmId=${toString cfg.vm.id}
      VmHost=${lib.escapeShellArg cfg.vm.host}
      VmUser=${lib.escapeShellArg cfg.vm.user}
      CredFile=${lib.escapeShellArg cfg.credentialsFile}
      ShutdownTimeout=${toString cfg.shutdownTimeout}
      BootTimeout=${toString cfg.bootTimeout}
      DefaultModel=${lib.escapeShellArg (if cfg.model == null then "" else cfg.model)}

      case "''${1:-}" in
        -h|--help)
          echo "Usage: llm [model]"
          echo "Shuts down other VMs on $ProxmoxHost, starts VM $VmId, and opens an Ollama chat on $VmHost."
          exit 0
          ;;
      esac
      Model="''${1:-$DefaultModel}"

      # Passwords: optional, one per host. Values are taken verbatim after the
      # first '=', so passwords may contain '=' and spaces.
      ProxmoxPass=""
      LlmPass=""
      if [[ -e "$CredFile" ]]; then
        if [[ ! -r "$CredFile" ]]; then
          gum log --level error "$CredFile exists but $(id -un) can't read it. Fix: sudo chown $(id -un) $CredFile"
          exit 1
        fi
        CredMode="$(stat -c %a "$CredFile")"
        if [[ "$CredMode" != 600 && "$CredMode" != 400 ]]; then
          gum log --level warn "$CredFile is mode $CredMode; it holds passwords, so: chmod 600 $CredFile"
        fi
        while IFS='=' read -r Key Value || [[ -n "$Key" ]]; do
          Value="''${Value%$'\r'}"
          case "$Key" in
            proxmox_password) ProxmoxPass="$Value" ;;
            llm_password) LlmPass="$Value" ;;
          esac
        done < "$CredFile"
      else
        gum log --level warn "No $CredFile; ssh will use keys or ask for passwords."
      fi

      SshOpts=(
        -o ConnectTimeout=10
        # First connection to a host trusts its key; a key that later changes
        # is still refused.
        -o StrictHostKeyChecking=accept-new
      )

      # RunSsh PASSWORD SSH_ARGS...: feed the password through sshpass when
      # we have one, otherwise plain ssh (keys or a normal prompt).
      RunSsh() {
        local Pass="$1"
        shift
        if [[ -n "$Pass" ]]; then
          SSHPASS="$Pass" sshpass -e ssh "''${SshOpts[@]}" -o NumberOfPasswordPrompts=1 "$@"
        else
          # shellcheck disable=SC2029  # the remote command is built client-side on purpose
          ssh "''${SshOpts[@]}" "$@"
        fi
      }

      # Single-quote a string for the remote shell, whatever that shell is.
      Quote() {
        local Escaped="''${1//\'/\'\\\'\'}"
        printf "'%s'" "$Escaped"
      }

      # Explain the sshpass-specific exit codes; anything else ssh already
      # printed its own reason for.
      ExplainSshFailure() {
        local Rc="$1" Target="$2"
        case "$Rc" in
          5) gum log --level error "Wrong password for $Target. Check $CredFile." ;;
          255) gum log --level error "SSH to $Target failed (see above)." ;;
        esac
      }

      PortOpen() {
        timeout 3 bash -c "echo > /dev/tcp/$1/22" 2>/dev/null
      }

      # 1. Proxmox: other VMs off, LLM VM on.
      if ! PortOpen "$ProxmoxHost"; then
        gum log --level error "Proxmox host $ProxmoxHost isn't reachable on port 22. It looks to be down."
        exit 1
      fi

      gum log --level info "Preparing VM $VmId on $ProxmoxHost..."
      Rc=0
      RunSsh "$ProxmoxPass" "$ProxmoxUser@$ProxmoxHost" \
        "bash -c $(Quote "$(< ${pveScript})") llm-chat $VmId $ShutdownTimeout" || Rc=$?
      if (( Rc != 0 )); then
        ExplainSshFailure "$Rc" "$ProxmoxUser@$ProxmoxHost"
        exit "$Rc"
      fi

      # 2. Wait for the VM's sshd.
      if ! PortOpen "$VmHost"; then
        gum log --level info "Waiting up to $BootTimeout seconds for $VmHost to boot..."
        Deadline=$((SECONDS + BootTimeout))
        until PortOpen "$VmHost"; do
          if (( SECONDS >= Deadline )); then
            gum log --level error "$VmHost still isn't answering on port 22 after $BootTimeout seconds. Check the VM console in Proxmox."
            exit 1
          fi
          sleep 2
        done
      fi

      # 3. Chat.
      Rc=0
      RunSsh "$LlmPass" -t "$VmUser@$VmHost" \
        "sh -c $(Quote "$(< ${chatScript})") llm-chat $(Quote "$Model")" || Rc=$?
      if (( Rc != 0 )); then
        ExplainSshFailure "$Rc" "$VmUser@$VmHost"
      fi
      exit "$Rc"
    '';
  };
in
{
  options.myOptions.llmChat = {
    enable = lib.mkEnableOption "the `llm` launcher for the Ollama VM on Proxmox";

    proxmox = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "proxmox.lan";
        description = "Hostname or IP of the Proxmox host.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user on the Proxmox host. Needs to be able to run qm.";
      };
    };

    vm = {
      id = lib.mkOption {
        type = lib.types.ints.positive;
        default = 103;
        description = "Proxmox VMID of the Ollama VM. Every other running VM is shut down.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "192.168.10.24";
        description = "Hostname or IP of the Ollama VM (its DHCP reservation).";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = config.myOptions.user.name;
        defaultText = lib.literalExpression "config.myOptions.user.name";
        description = "SSH user on the Ollama VM.";
      };
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qwen3:14b";
      description = ''
        Model to chat with when `llm` is run with no argument. null picks the
        newest model in `ollama list` on the VM.
      '';
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/llm-chat.cred";
      description = ''
        File with proxmox_password= and llm_password= lines, owned by the user
        who runs `llm`, mode 0600. Kept outside the store and the repo.
      '';
    };

    shutdownTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Seconds to wait for each other VM to shut down cleanly before giving up.";
    };

    bootTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Seconds to wait for the Ollama VM to accept SSH after starting it.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ llm ];
  };
}
