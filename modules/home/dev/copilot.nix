# modules/home/dev/copilot.nix — GitHub Copilot CLI dotfiles.
#
# Symlinks ~/.copilot/copilot-instructions.md (custom instructions injected
# into every Copilot CLI session). nixhome ships a generic instructions
# file under `config/copilot/copilot-instructions.md`; hosts get it by
# default. Override `instructionsFile` to use your own.
#
# Skills are handled separately via modules.home.skills.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.copilot;
  bundledInstructions = ../../../config/copilot/copilot-instructions.md;
in
{
  options.modules.home.dev.copilot = {
    enable = lib.mkEnableOption "Copilot CLI user configuration";

    useBundledInstructions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use nixhome's bundled copilot-instructions.md when `instructionsFile` is null.";
    };

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to ~/.copilot/copilot-instructions.md. Symlinked via
        mkOutOfStoreSymlink. If null and `useBundledInstructions` is true,
        nixhome's bundled instructions are used.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge [
      (lib.mkIf (cfg.instructionsFile != null) {
        ".copilot/copilot-instructions.md".source =
          config.lib.file.mkOutOfStoreSymlink (toString cfg.instructionsFile);
      })
      (lib.mkIf (cfg.instructionsFile == null && cfg.useBundledInstructions) {
        ".copilot/copilot-instructions.md".source = bundledInstructions;
      })
    ];
  };
}
