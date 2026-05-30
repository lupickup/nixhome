# modules/home/shell/starship.nix — Starship prompt with zsh integration.
#
# nixhome ships an opinionated config.toml under `config/starship.toml`
# (catppuccin_mocha theme). Hosts get it for free; override with a custom
# `configFile` if you want your own.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.starship;
  bundledConfig = ../../../config/starship.toml;
in
{
  options.modules.home.shell.starship = {
    enable = lib.mkEnableOption "Starship prompt";

    useBundledConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use nixhome's bundled starship.toml when `configFile` is null. Set
        to false to fall back to Starship's built-in defaults.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a custom starship.toml. If set, it is symlinked to
        ~/.config/starship.toml via mkOutOfStoreSymlink so edits write back
        to the source. If null and `useBundledConfig` is true, nixhome's
        bundled config is used.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
    };

    xdg.configFile = lib.mkMerge [
      (lib.mkIf (cfg.configFile != null) {
        "starship.toml".source =
          config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
      })
      (lib.mkIf (cfg.configFile == null && cfg.useBundledConfig) {
        "starship.toml".source = bundledConfig;
      })
    ];
  };
}
