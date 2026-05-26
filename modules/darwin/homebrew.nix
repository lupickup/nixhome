# modules/darwin/homebrew.nix — gate nix-darwin's Homebrew management on
# the dotfiles.darwin.homebrew.mode option.
#
# Three modes:
#   nix-homebrew : nix-darwin owns brew + bundle. casks/brews/taps come from
#                  the host or a private overlay via the options below.
#   system-brew  : an existing system Homebrew is used (e.g. managed corporate
#                  Mac). nix-darwin must NOT take over. Use a separate
#                  activation script in the host or private overlay to install
#                  packages via the system brew.
#   disabled     : no Homebrew at all.
#
# This module declares the OPTIONS but does not declare nix-homebrew as a
# module input. Hosts/overlays that need it pass it in via their own
# specialArgs and add nix-homebrew.darwinModules.nix-homebrew to their
# imports list. Keeps nixhome OSS-clean (no nix-homebrew dependency leak).

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.darwin.homebrew;
  mode = config.dotfiles.darwin.homebrew.mode;
in
{
  options.modules.darwin.homebrew = {
    enable = lib.mkEnableOption "Homebrew via nix-darwin";

    taps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    brews = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    casks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    onActivationCleanup = lib.mkOption {
      type = lib.types.enum [ "none" "uninstall" "zap" ];
      default = "zap";
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin && mode == "nix-homebrew") {
    homebrew = {
      enable = true;
      inherit (cfg) taps brews casks;
      onActivation.cleanup = cfg.onActivationCleanup;
      onActivation.autoUpdate = true;
      onActivation.upgrade = true;
    };
  };
}
