# modules/home/dev/copilot.nix — GitHub Copilot CLI dotfiles.
#
# Symlinks ~/.copilot/copilot-instructions.md (custom instructions injected
# into every Copilot CLI session). Skills are handled separately via
# modules.home.skills (which deploys to both Claude and Copilot).

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.copilot;
in
{
  options.modules.home.dev.copilot = {
    enable = lib.mkEnableOption "Copilot CLI user configuration";

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to ~/.copilot/copilot-instructions.md. Symlinked via
        mkOutOfStoreSymlink. Loaded by Copilot CLI as global instructions.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkIf (cfg.instructionsFile != null) {
      ".copilot/copilot-instructions.md".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.instructionsFile);
    };
  };
}
