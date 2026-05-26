# modules/home/dev/gsd.nix — Get-Shit-Done (GSD) helper scripts + preferences.
#
# Deploys a configurable set of bin/ scripts (gsd-src*, gsd-v1-src*, gsd-dh-*,
# etc.) and the ~/.gsd/PREFERENCES.md + ~/.gsd/GSD-ECOSYSTEM.md symlinks. All
# paths are passed in by the host; this module just owns the wiring shape.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.gsd;
in
{
  options.modules.home.dev.gsd = {
    enable = lib.mkEnableOption "GSD source-build scripts and preferences";

    bins = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          gsd-src = "''${dotfilesDir}/scripts/gsd-src.sh";
          gsd-src-install = "''${dotfilesDir}/scripts/gsd-src-install.sh";
          verify-gsd-bootstrap = "''${dotfilesDir}/scripts/verify-gsd-bootstrap.sh";
        }
      '';
      description = "Map of bin name → script path. Deployed to ~/bin/<name>.";
    };

    preferencesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to ~/.gsd/PREFERENCES.md. Symlinked via mkOutOfStoreSymlink.";
    };

    ecosystemFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to ~/.gsd/GSD-ECOSYSTEM.md. Symlinked via mkOutOfStoreSymlink.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.file = lib.mkMerge (
        lib.mapAttrsToList (binName: src: {
          "bin/${binName}" = {
            text = ''exec "${toString src}" "$@"'';
            executable = true;
          };
        }) cfg.bins
      );
    }

    (lib.mkIf (cfg.preferencesFile != null) {
      home.file.".gsd/PREFERENCES.md".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.preferencesFile);
    })

    (lib.mkIf (cfg.ecosystemFile != null) {
      home.file.".gsd/GSD-ECOSYSTEM.md".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.ecosystemFile);
    })
  ]);
}
