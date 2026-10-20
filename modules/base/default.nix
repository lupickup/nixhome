# modules/base/default.nix — option schemas shared by every nixhome host.
#
# This module is loaded automatically by mkDotfilesFlake for both home-manager
# and nix-darwin configurations. It declares:
#
#   - `dotfiles.context.*` — semantic facts about the host (replaces today's
#     bag of isWSL/isRemote/isDarwin/hostname extraSpecialArgs).
#   - `dotfiles.darwin.*` — Darwin-only knobs (homebrew mode, Nix installer).
#
# App modules CONSUME these options to gate behaviour:
#
#   config = lib.mkIf (cfg.enable && config.dotfiles.context.platform == "linux") {
#     ...
#   };
#
# Hosts set them at the top of their config block:
#
#   dotfiles.context = {
#     platform = "wsl";
#     identity = "personal";
#     ...
#   };
#
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  isDarwinHost = pkgs.stdenv.hostPlatform.isDarwin;
  isLinuxHost = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.dotfiles = {
    context = {
      platform = mkOption {
        type = types.enum [ "darwin" "linux" "wsl" ];
        # Defaults to the obvious choice; WSL must opt in explicitly because
        # there's no stable way to detect WSL purely from pkgs.stdenv.
        default = if isDarwinHost then "darwin" else "linux";
        description = ''
          Host platform. Influences clipboard backend, font installation,
          credential backend defaults, and which platform modules are active.
          WSL must be set explicitly — auto-detection picks "linux" otherwise.
        '';
      };

      location = mkOption {
        type = types.enum [ "local" "remote" ];
        default = "local";
        description = ''
          Whether this host is used directly (`local` — workstation, laptop)
          or accessed primarily via SSH (`remote` — dev VM, devbox). Affects
          SSH agent wiring, X/wayland defaults, and which helper scripts get
          deployed.
        '';
      };

      identity = mkOption {
        type = types.strMatching "[a-z][a-z0-9-]*";
        default = "personal";
        description = ''
          Label of the identity profile this host uses for top-level git
          user, email and signing. Identity profiles (see
          `lib.mkIdentityProfile`) are declared by the private overlays that
          own them; the profile whose name matches this label activates.
        '';
      };

      capability = mkOption {
        type = types.enum [ "minimal-shell" "dev" "desktop" ];
        default = "dev";
        description = ''
          Capability level — determines the package set and which apps are
          enabled by default. `minimal-shell` = remote-shell baseline (zsh,
          starship, zellij, neovim, common CLI). `dev` = adds compilers,
          language toolchains, AI assistants. `desktop` = adds GUI apps,
          fonts, terminal emulators.
        '';
      };

      managedHost = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether this host is corporate-provisioned with externally-managed
          shell init scripts, SSH config, PAM, etc. When true, nix-darwin
          and home-manager skip writes to those paths (`/etc/zshrc`,
          `programs.ssh`, security.pam.services.sudo_local, etc.).
        '';
      };

      aiProfile = mkOption {
        type = types.enum [ "anthropic" "copilot" ];
        default = "anthropic";
        description = ''
          Default AI tool routing. `anthropic` = Claude Code primary,
          native web search. `copilot` = GitHub Copilot primary, brave search
          fallback. Read by opencode config variant and codex config variant.
        '';
      };

      credentialBackend = mkOption {
        type = types.enum [ "none" "linux-gcm" "windows-gcm-wsl" "macos-gcm" ];
        default =
          if isDarwinHost then "macos-gcm"
          else "none";
        description = ''
          How git credentials are stored and prompted.
          - `none`: no helper (rely on SSH-only).
          - `linux-gcm`: native git-credential-manager via apt.
          - `windows-gcm-wsl`: invoke Windows-side GCM via /mnt/c interop.
          - `macos-gcm`: Homebrew-installed git-credential-manager.
        '';
      };

      clipboardBackend = mkOption {
        type = types.enum [ "wl-clipboard" "pbcopy" "clip-exe-wsl" "xclip" "none" ];
        default =
          if isDarwinHost then "pbcopy"
          else "wl-clipboard";
        description = ''
          Clipboard integration. Used by zellij copy_command and any tool
          that asks "how do I get text into the system clipboard".
        '';
      };
    };

    darwin = {
      homebrew.mode = mkOption {
        type = types.enum [ "nix-homebrew" "system-brew" "disabled" ];
        default = "nix-homebrew";
        description = ''
          How Homebrew is managed on this Darwin host.
          - `nix-homebrew`: nix-darwin owns brew + bundle (personal Macs).
          - `system-brew`: an existing system Homebrew installation is used;
            nix-darwin must NOT take over (managed corporate Macs).
          - `disabled`: no Homebrew at all.
        '';
      };

      nixInstaller = mkOption {
        type = types.enum [ "traditional" "determinate" ];
        default = "traditional";
        description = ''
          Which Nix installer is in use. Determinate Systems' installer
          manages its own daemon and nix.conf; nix-darwin must not try to
          manage them too (set `nix.enable = false` in that case).
        '';
      };
    };
  };
}
