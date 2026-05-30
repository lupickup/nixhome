# modules/home/dev/dev-box.nix — remote dev-box conveniences.
#
# For hosts that are reached primarily via SSH and forward an SSH agent
# (1Password, KeePassXC, plain ssh-agent) from a workstation. Solves the
# annoying-but-universal problems:
#
#   1. Forwarded agent socket changes path on every reconnect; long-lived
#      sessions (zellij, tmux) end up pointing at a stale socket.
#   2. When the workstation is unreachable, you still need to do git push
#      or sign a commit — you want a VM-local agent as a fallback.
#   3. Git config needs to call into the right wrapper for both ssh and
#      signing — without rebuilding home-manager every time.
#
# This module ships THREE generic wrapper scripts that resolve a live socket
# at command time (preferring forwarded, falling back to VM-local), plus
# a long-lived ssh-agent systemd user unit so there's always a local
# fallback socket at $HOME/.ssh/agent.sock.
#
# Usage in a host:
#
#   modules.home.dev.dev-box = {
#     enable = true;
#     installGssapi = true;        # if you SSH to Kerberos-auth services
#     enableStableAgent = true;    # local fallback ssh-agent.service
#   };
#
# Then in the git module:
#
#   modules.home.shell.git = {
#     sshCommand     = "${config.home.homeDirectory}/.local/bin/ssh-vscode-wrapper";
#     signing.program = "${config.home.homeDirectory}/.local/bin/ssh-sign-wrapper";
#   };
#
# Note: this module is about USER-SPACE conveniences. OS-level Microsoft
# DevBox / Intune provisioning (image baseline, mdm policies, corporate
# software) is handled by the image build / Ansible — not nix.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.dev-box;
  ctx = config.dotfiles.context;

  wrappers = {
    "ssh-vscode-wrapper"      = ../../../scripts/ssh-vscode-wrapper;
    "ssh-sign-wrapper"        = ../../../scripts/ssh-sign-wrapper;
    "resolve-vscode-ssh-sock" = ../../../scripts/resolve-vscode-ssh-sock;
  };
in
{
  options.modules.home.dev.dev-box = {
    enable = lib.mkEnableOption "remote dev-box conveniences (SSH wrappers, stable agent)";

    installGssapi = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install pkgs.openssh_gssapi (OpenSSH with GSSAPI/Kerberos support).
        Needed when you SSH to Kerberos-authenticated services from this
        box (common on corporate dev VMs).
      '';
    };

    installSshWrappers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install ssh-vscode-wrapper, ssh-sign-wrapper, and
        resolve-vscode-ssh-sock into ~/.local/bin. These resolve a live
        forwarded or VM-local SSH agent socket at command time.
      '';
    };

    enableStableAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run a long-lived ssh-agent.service as a systemd user unit. Provides
        a fallback agent socket at `stableAgentSocket` for when the
        forwarded agent isn't available. Set DEVBOX_SSH_AUTH_SOCK env var
        to the socket path to make the wrappers find it.
      '';
    };

    stableAgentSocket = lib.mkOption {
      type = lib.types.str;
      default = "%h/.ssh/agent.sock";
      description = ''
        Path to the local fallback ssh-agent socket. systemd `%h` expands
        to the home directory. Also exported via DEVBOX_SSH_AUTH_SOCK by
        default so the wrapper scripts can find it.
      '';
    };

    exportDevboxSocketEnv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Export DEVBOX_SSH_AUTH_SOCK=<stableAgentSocket> as a session
        variable so the wrapper scripts pick up the local fallback.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # SSH wrapper scripts → ~/.local/bin/
    (lib.mkIf cfg.installSshWrappers {
      home.file = lib.mapAttrs' (binName: src:
        lib.nameValuePair ".local/bin/${binName}" {
          source = src;
          executable = true;
        }
      ) wrappers;
    })

    # GSSAPI-enabled openssh
    (lib.mkIf cfg.installGssapi {
      home.packages = [ pkgs.openssh_gssapi ];
    })

    # Stable local ssh-agent fallback (Linux only — uses systemd user units)
    (lib.mkIf (cfg.enableStableAgent && ctx.platform != "darwin") {
      systemd.user.services.devbox-ssh-agent = {
        Unit = {
          Description = "Stable dev-box SSH agent fallback";
          Documentation = "man:ssh-agent(1)";
        };
        Service = {
          Type = "simple";
          ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${cfg.stableAgentSocket}";
          ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a ${cfg.stableAgentSocket}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    # Export the DEVBOX_SSH_AUTH_SOCK convention so wrappers find the fallback
    (lib.mkIf cfg.exportDevboxSocketEnv {
      home.sessionVariables.DEVBOX_SSH_AUTH_SOCK =
        # Replace systemd %h with $HOME for shell env
        lib.replaceStrings [ "%h" ] [ "$HOME" ] cfg.stableAgentSocket;
    })
  ]);
}
