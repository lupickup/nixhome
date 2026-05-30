# Example "remote dev box" host — Linux VM you SSH into and edit on.
#
# Builds with:
#   nix build .#homeConfigurations.example-devbox.activationPackage
#
# This shows the pattern most people on a corporate-provisioned remote
# dev VM (Microsoft DevBox / Cloud Workstation / personal cloud VM)
# actually want:
#
#   - Bundled starship/zellij/copilot defaults (zero-config baseline).
#   - dev-box module: SSH-wrapper scripts + stable agent fallback +
#     DEVBOX_SSH_AUTH_SOCK convention.
#   - dotfiles.context.location = "remote" → git module wires the wrappers.
#   - dotfiles.context.credentialBackend = "none" → SSH-only auth.
#
# What this host does NOT do:
#
#   - Install corporate software (Intune / Ansible / image baseline owns that).
#   - Set an identity profile email / signing key (forkers wire their own).
#   - Touch /etc/ssh/ssh_config or PAM (use managedHost = true if the box
#     is corporate-provisioned and you want HM to keep its hands off).

{ lib, ... }:

{
  system = "x86_64-linux";
  username = "lupickup";

  config = { config, pkgs, lib, ... }: {
    dotfiles.context = {
      platform = "linux";
      location = "remote";
      identity = "personal";
      capability = "dev";
      credentialBackend = "none";
      clipboardBackend = "wl-clipboard";
    };

    # Shell baseline — uses nixhome's bundled config defaults.
    modules.home.shell.zsh.enable = true;
    modules.home.shell.starship.enable = true;
    modules.home.shell.zellij.enable = true;

    # Remote dev-box conveniences.
    modules.home.dev.dev-box = {
      enable = true;
      installGssapi = true;          # most corporate dev VMs need Kerberos
      enableStableAgent = true;      # local fallback ssh-agent
      installSshWrappers = true;     # ~/.local/bin/ssh-{vscode,sign}-wrapper
    };

    # Git wired to use the dev-box SSH wrappers.
    modules.home.shell.git = {
      enable = true;
      sshCommand     = "${config.home.homeDirectory}/.local/bin/ssh-vscode-wrapper";
      signing.program = "${config.home.homeDirectory}/.local/bin/ssh-sign-wrapper";
      # Fork-specific identity goes in your private overlay; the OSS example
      # leaves user.name / user.email / signing.key unset.
    };

    # AI tooling — opt in to whatever's installed on the box.
    modules.home.dev.copilot.enable = true;
    modules.home.dev.claude.enable  = true;
    modules.home.skills = {
      enable = true;
      bundledSkills.checkpoint.enable = true;
    };

    # Linux platform glue + Linuxbrew path.
    modules.home.platform.linux = {
      enable = true;
      enableDesktopFonts = false;   # remote dev box doesn't need them
    };
  };
}
