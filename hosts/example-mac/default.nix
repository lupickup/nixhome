# Example public macOS host — reference for forkers.
#
# Builds with `nix build .#darwinConfigurations.example-mac.system`.
# Doesn't deploy anything beyond the home-manager skeleton; copy this file and
# add your own enable flags.
{ lib, ... }:

{
  system = "aarch64-darwin";
  username = "alice";
  homeDirectory = "/Users/alice";

  config = { config, pkgs, ... }: {
    dotfiles.context = {
      platform = "darwin";
      location = "local";
      identity = "personal";
      capability = "desktop";
    };

    dotfiles.darwin = {
      homebrew.mode = "nix-homebrew";
      nixInstaller = "traditional";
    };

    # Required for Darwin builds.
    system.stateVersion = 5;
    system.primaryUser = "alice";

    # No modules enabled by default — forker turns on what they want here.
  };
}
