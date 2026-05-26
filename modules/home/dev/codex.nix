# modules/home/dev/codex.nix — Codex CLI configuration.
#
# Codex itself isn't packaged here. This module just symlinks the user's
# ~/.config/codex/config.toml to one of their config files. The choice is
# typically driven by dotfiles.context.aiProfile but this module is
# intentionally NOT identity-aware — the host or identity profile passes
# the right path in via `configFile`.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.codex;
in
{
  options.modules.home.dev.codex = {
    enable = lib.mkEnableOption "Codex CLI configuration";

    installPackage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install pkgs.codex into home.packages. Disabled by default because
        Codex is also commonly installed via npm/brew/cargo; opt in if you
        want the nixpkgs build.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a codex config.toml. Symlinked to ~/.config/codex/config.toml.";
    };

    workspaceConfigFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          "workspaces/mydev.toml" = "''${dotfilesDir}/config/codex/workspaces/mydev.toml";
        }
      '';
      description = ''
        Additional codex config files (e.g. workspace presets). Each entry
        is symlinked to ~/.config/codex/<basename>.
      '';
    };

    extraBins = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          codex-copilot-auth = "''${dotfilesDir}/scripts/codex-copilot-auth";
          codex-workspace = "''${dotfilesDir}/scripts/codex-workspace.sh";
        }
      '';
      description = "Map of bin name → script path. Deployed to ~/bin/<name>.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.installPackage {
      home.packages = [ pkgs.codex ];
    })

    (lib.mkIf (cfg.configFile != null) {
      xdg.configFile."codex/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
    })

    {
      xdg.configFile = lib.mkMerge (
        lib.mapAttrsToList (rel: src: {
          "codex/${rel}".source =
            config.lib.file.mkOutOfStoreSymlink (toString src);
        }) cfg.workspaceConfigFiles
      );
    }

    {
      home.file = lib.mkMerge (
        lib.mapAttrsToList (binName: src: {
          "bin/${binName}" = {
            text = ''exec "${toString src}" "$@"'';
            executable = true;
          };
        }) cfg.extraBins
      );
    }
  ]);
}
