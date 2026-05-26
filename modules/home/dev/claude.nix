# modules/home/dev/claude.nix — Claude Code CLI integration.
#
# Claude Code itself isn't packaged here (installed via npm/brew typically).
# This module manages the user-level dotfiles: settings.json, optional
# initial ~/.claude.json seed, and symlinks for skills (handled separately
# via modules.home.skills).

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.claude;
in
{
  options.modules.home.dev.claude = {
    enable = lib.mkEnableOption "Claude Code user configuration";

    seedConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a starter ~/.claude.json. Copied (not symlinked) at
        activation time so Claude can write back to it. Only seeded if
        ~/.claude.json does not already exist.
      '';
    };

    settingsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to ~/.claude/settings.json. Symlinked via
        mkOutOfStoreSymlink.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.settingsFile != null) {
      home.file.".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.settingsFile);
    })

    (lib.mkIf (cfg.seedConfigFile != null) {
      home.activation.seedClaudeJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "$HOME/.claude.json" ]; then
          cp "${toString cfg.seedConfigFile}" "$HOME/.claude.json"
          chmod 600 "$HOME/.claude.json"
        fi
      '';
    })
  ]);
}
