# Example public Linux host — reference for forkers.
#
# Builds with `nix build .#homeConfigurations.example-linux.activationPackage`.
# Doesn't deploy anything beyond the home-manager skeleton; the user is expected
# to copy this file and add their own enable flags.
{ lib, ... }:

{
  system = "x86_64-linux";
  username = "alice";
  homeDirectory = "/home/alice";

  config = { config, pkgs, ... }: {
    dotfiles.context = {
      platform = "linux";
      location = "local";
      identity = "personal";
      capability = "dev";
      clipboardBackend = "wl-clipboard";
      credentialBackend = "none";
    };

    # No modules enabled by default — forker turns on what they want here.
    # Example:
    #   modules.home.shell.zsh.enable = true;
    #   modules.home.shell.starship.enable = true;
    #   modules.home.dev.claude.enable = true;
  };
}
