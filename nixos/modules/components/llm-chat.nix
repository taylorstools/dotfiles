# `llm`: one command to get to the Ollama VM.
#
# It SSHes to the Proxmox host, shuts down every other running VM there,
# starts the LLM VM if it isn't already running, waits for Open WebUI on it to
# come up, then opens it in the browser.
#
# Only QEMU VMs (qm) are shut down. LXC containers (pct), such as the tang
# server, are never touched.
#
# Usage:
#   llm                        # open Open WebUI in the browser
#   llm --terminal             # chat in the terminal instead (`ollama run`
#   llm --terminal qwen3:14b   #   over SSH), newest model or a named one;
#                              #   /bye or Ctrl+D to leave
# Either way the VM keeps running afterwards.
#
# The first run asks for the root password on Proxmox (and, the first time
# --terminal is used, your password on the VM) and saves them to
# credentialsFile (/etc/llm-chat.cred: owned by you, mode 0600, created with
# sudo once, never in git). Leave a prompt empty to use SSH keys for that host
# instead. A rejected password is asked for again and re-saved;
# `sudo rm /etc/llm-chat.cred` to start over.
#
# One-time setup on the VM (Debian 13), over `ssh taylor@<vm>`:
#   sudo apt install -y docker.io
#   sudo docker run -d --name open-webui --restart always --network host \
#     -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
#     -v open-webui:/app/backend/data \
#     ghcr.io/open-webui/open-webui:main
# Host networking lets the container reach Ollama on the VM's loopback, so
# Ollama's unauthenticated API never has to listen on the LAN; only Open WebUI
# (which has its own login) does, on port 8080. The first account created in
# it becomes the admin. To update it later:
#   sudo docker pull ghcr.io/open-webui/open-webui:main
#   sudo docker rm -f open-webui    # then the `docker run` above again
# (chats and settings live in the open-webui volume and survive this).

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

    # qm only lists QEMU VMs, so LXC containers (tang) are left running.
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
    runtimeInputs = with pkgs; [ bash coreutils curl gnugrep gum openssh sshpass util-linux xdg-utils ];
    text = ''
      # Config
      ProxmoxHost=${lib.escapeShellArg cfg.proxmox.host}
      ProxmoxUser=${lib.escapeShellArg cfg.proxmox.user}
      VmId=${toString cfg.vm.id}
      VmHost=${lib.escapeShellArg cfg.vm.host}
      VmUser=${lib.escapeShellArg cfg.vm.user}
      WebUiPort=${toString cfg.webUi.port}
      CredFile=${lib.escapeShellArg cfg.credentialsFile}
      ShutdownTimeout=${toString cfg.shutdownTimeout}
      BootTimeout=${toString cfg.bootTimeout}
      DefaultModel=${lib.escapeShellArg (if cfg.model == null then "" else cfg.model)}

      ProxmoxTarget="$ProxmoxUser@$ProxmoxHost"
      VmTarget="$VmUser@$VmHost"
      WebUiUrl="http://$VmHost:$WebUiPort"

      Usage() {
        echo "Usage: llm                      open Open WebUI ($WebUiUrl) in the browser"
        echo "       llm --terminal [model]   chat in the terminal over SSH instead"
        echo
        echo "Either way, first shuts down other VMs (not LXC containers) on $ProxmoxHost"
        echo "and starts VM $VmId. Saved SSH passwords: $CredFile (sudo rm it to be asked again)."
      }

      Mode="web"
      case "''${1:-}" in
        -h|--help)
          Usage
          exit 0
          ;;
        -t|--terminal)
          Mode="terminal"
          shift
          ;;
      esac
      if [[ "$Mode" == web && $# -gt 0 ]]; then
        Usage >&2
        exit 2
      fi
      Model="''${1:-$DefaultModel}"

      # Saved passwords: key=value lines, one per host. Values are taken
      # verbatim after the first '=', so they may contain '=' and spaces. A key
      # with an empty value means "nothing saved, use SSH keys or ask".
      declare -A Passwords=()
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
          case "$Key" in
            proxmox_password|llm_password) Passwords[$Key]="''${Value%$'\r'}" ;;
          esac
        done < "$CredFile"
      fi

      # SaveCred KEY VALUE: create the file on first use (0600, owned by the
      # user running llm; sudo only if its directory isn't ours), then replace
      # KEY's line. Rewritten in place so the owner and mode stick.
      SaveCred() {
        local Key="$1" Value="$2" Others
        if [[ ! -e "$CredFile" ]]; then
          if [[ -w "$(dirname "$CredFile")" ]]; then
            install -m 0600 /dev/null "$CredFile"
          else
            gum log --level info "Creating $CredFile (asks sudo once)..."
            sudo install -m 0600 -o "$(id -un)" -g "$(id -gn)" /dev/null "$CredFile"
          fi
        fi
        Others="$(grep -v "^$Key=" "$CredFile" || true)"
        {
          if [[ -n "$Others" ]]; then
            printf '%s\n' "$Others"
          fi
          printf '%s=%s\n' "$Key" "$Value"
        } > "$CredFile"
      }

      # AskPass KEY TARGET: prompt for TARGET's SSH password and save it.
      AskPass() {
        local Key="$1" Target="$2"
        if [[ ! -t 0 ]]; then
          gum log --level error "No saved password for $Target and no terminal to ask on. Run llm from a terminal once."
          exit 1
        fi
        Passwords[$Key]="$(gum input --password \
          --header "SSH password for $Target (leave empty to use SSH keys):")"
        SaveCred "$Key" "''${Passwords[$Key]}"
      }

      # Ask for anything this run needs and hasn't saved yet up front, so a
      # first run doesn't stop halfway through (after the other VMs are
      # already shut down) to ask. The VM password is only needed for SSH
      # into the VM, so only for --terminal.
      Needed=(proxmox_password)
      if [[ "$Mode" == terminal ]]; then
        Needed+=(llm_password)
      fi
      Announced=0
      for Key in "''${Needed[@]}"; do
        if [[ ! -v Passwords[$Key] ]]; then
          if (( ! Announced )); then
            gum log --level info "Saving SSH passwords to $CredFile. You won't be asked again."
            Announced=1
          fi
          case "$Key" in
            proxmox_password) AskPass "$Key" "$ProxmoxTarget" ;;
            llm_password) AskPass "$Key" "$VmTarget" ;;
          esac
        fi
      done

      SshOpts=(
        -o ConnectTimeout=10
        # First connection to a host trusts its key; a key that later changes
        # is still refused.
        -o StrictHostKeyChecking=accept-new
      )

      # RunSsh PASSWORD SSH_ARGS...: feed the password through sshpass when
      # there is one, otherwise plain ssh (keys or a normal prompt).
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

      # SshAs KEY TARGET SSH_ARGS...: ssh with the password saved under KEY.
      # sshpass exits 5 on a rejected password; ask again (and re-save) up to
      # twice before giving up.
      SshAs() {
        local Key="$1" Target="$2" Tries=1 Rc
        shift 2
        while :; do
          Rc=0
          RunSsh "''${Passwords[$Key]}" "$@" || Rc=$?
          if (( Rc == 5 && Tries < 3 )) && [[ -t 0 ]]; then
            gum log --level warn "$Target rejected the saved password."
            AskPass "$Key" "$Target"
            Tries=$((Tries + 1))
            continue
          fi
          case "$Rc" in
            5) gum log --level error "$Target rejected the password. Fix it in $CredFile or delete that line to be asked again." ;;
            255) gum log --level error "SSH to $Target failed (see above)." ;;
          esac
          return "$Rc"
        done
      }

      # Single-quote a string for the remote shell, whatever that shell is.
      Quote() {
        local Escaped="''${1//\'/\'\\\'\'}"
        printf "'%s'" "$Escaped"
      }

      # PortOpen HOST PORT
      PortOpen() {
        timeout 3 bash -c "echo > /dev/tcp/$1/$2" 2>/dev/null
      }

      WebUiReady() {
        curl -fsS --max-time 3 "$WebUiUrl/health" >/dev/null 2>&1
      }

      # WaitFor DESCRIPTION HINT CHECK...: run CHECK until it succeeds or
      # BootTimeout runs out. Silent if it's already up.
      WaitFor() {
        local What="$1" Hint="$2" Deadline
        shift 2
        if "$@"; then
          return 0
        fi
        gum log --level info "Waiting up to $BootTimeout seconds for $What..."
        Deadline=$((SECONDS + BootTimeout))
        until "$@"; do
          if (( SECONDS >= Deadline )); then
            gum log --level error "$What still isn't up after $BootTimeout seconds. $Hint"
            exit 1
          fi
          sleep 2
        done
      }

      # 1. Proxmox: other VMs off, LLM VM on.
      if ! PortOpen "$ProxmoxHost" 22; then
        gum log --level error "Proxmox host $ProxmoxHost isn't reachable on port 22. It looks to be down."
        exit 1
      fi

      gum log --level info "Preparing VM $VmId on $ProxmoxHost..."
      Rc=0
      SshAs proxmox_password "$ProxmoxTarget" "$ProxmoxTarget" \
        "bash -c $(Quote "$(< ${pveScript})") llm-chat $VmId $ShutdownTimeout" || Rc=$?
      if (( Rc != 0 )); then
        exit "$Rc"
      fi

      # 2a. Terminal chat over SSH.
      if [[ "$Mode" == terminal ]]; then
        WaitFor "SSH on $VmHost" "Check the VM console in Proxmox." PortOpen "$VmHost" 22
        Rc=0
        SshAs llm_password "$VmTarget" -t "$VmTarget" \
          "sh -c $(Quote "$(< ${chatScript})") llm-chat $(Quote "$Model")" || Rc=$?
        exit "$Rc"
      fi

      # 2b. Open WebUI. Its first start after an image update can take a few
      # minutes while it migrates and downloads its embedding model.
      WaitFor "Open WebUI at $WebUiUrl" \
        "Check the VM console in Proxmox, or on the VM: sudo docker logs open-webui" \
        WebUiReady

      if [[ -n "''${WAYLAND_DISPLAY:-}''${DISPLAY:-}" ]]; then
        gum log --level info "Opening $WebUiUrl"
        # Detached: xdg-open can block for as long as a freshly started
        # browser stays open.
        setsid -f xdg-open "$WebUiUrl" >/dev/null 2>&1
      else
        gum log --level info "Open WebUI is up at $WebUiUrl"
      fi
    '';
  };
in
{
  options.myOptions.llmChat = {
    enable = lib.mkEnableOption "the `llm` launcher for Open WebUI on the Ollama VM on Proxmox";

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
        description = "Proxmox VMID of the Ollama VM. Every other running VM (not LXC container) is shut down.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "llm.lan";
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
        Model for `llm --terminal` when no model is given. null picks the
        newest model in `ollama list` on the VM. Open WebUI has its own picker.
      '';
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/llm-chat.cred";
      description = ''
        File with proxmox_password= and llm_password= lines, owned by the user
        who runs `llm`, mode 0600. `llm` creates it and fills it in on first
        run. Kept outside the store and the repo.
      '';
    };

    shutdownTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = "Seconds to wait for each other VM to shut down cleanly before giving up.";
    };

    webUi.port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port Open WebUI listens on inside the VM.";
    };

    bootTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds to wait for the VM to come up after starting it: for Open
        WebUI to answer, or for SSH with --terminal. Open WebUI's first start
        after an update can take a few minutes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ llm ];
  };
}
