# modules/home/dev/codex.nix — Codex CLI configuration.
#
# Codex itself isn't packaged here. This module links the user's
# ~/.config/codex/config.toml to a writable, out-of-store config file, so
# Codex and its desktop app can keep writing settings back while the file
# stays tracked in the user's repo. The host passes the path via
# `configFile`; this module is intentionally not identity-aware.
#
# Keep tracked configs to defaults worth persisting. Model-pinned profiles
# go stale quickly, and Codex 0.134+ rejects a top-level `profile = "..."`
# selector and `[profiles.<name>]` tables; use `<name>.config.toml` files
# with `codex --profile <name>` instead. For policy the app must not relax,
# use system requirements (see modules/darwin/codex.nix).
#
# `exporter.enable` installs `codex-export`, which reads Codex's local thread
# databases read-only and renders threads as Markdown transcripts. The bundled
# `codex-import` skill uses it to continue Codex threads in GitHub Copilot:
#
#   modules.home.dev.codex = {
#     enable = true;
#     exporter.enable = true;
#   };
#   modules.home.skills.bundledSkills."codex-import".enable = true;

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
      description = "Path to a codex config.toml. Linked writable (out-of-store) to ~/.config/codex/config.toml.";
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
          codex-workspace = "''${dotfilesDir}/scripts/codex-workspace.sh";
        }
      '';
      description = "Map of bin name → script path. Deployed to ~/bin/<name>.";
    };

    exporter.enable = lib.mkEnableOption ''
      codex-export, which lists local Codex threads and renders them as
      Markdown transcripts (used by the bundled codex-import skill)'';
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.installPackage {
      home.packages = [ pkgs.codex ];
    })

    (lib.mkIf cfg.exporter.enable {
      home.packages = [
        (pkgs.writeShellScriptBin "codex-export" ''
          exec ${pkgs.python3}/bin/python3 ${../../../scripts/codex-export} "$@"
        '')
      ];
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
