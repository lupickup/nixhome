# modules/home/dev/opencode.nix — OpenCode configuration.
#
# Symlinks the user's chosen opencode.jsonc into ~/.config/opencode/.
# Often paired with modules.home.dev.gsd for the source-build scripts.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.dev.opencode;
in
{
  options.modules.home.dev.opencode = {
    enable = lib.mkEnableOption "OpenCode configuration";

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to opencode.jsonc. Symlinked to ~/.config/opencode/opencode.jsonc.";
    };

    extraBins = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Map of bin name → script path. Deployed to ~/bin/<name>.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.configFile != null) {
      xdg.configFile."opencode/opencode.jsonc".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
    })

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
