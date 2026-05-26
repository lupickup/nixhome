# modules/home/shell/starship.nix — Starship prompt with zsh integration.
#
# The OSS module ships Starship's default theme. To use a custom starship.toml:
#
#   modules.home.shell.starship = {
#     enable = true;
#     configFile = "''${dotfilesDir}/config/starship.toml";
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.starship;
in
{
  options.modules.home.shell.starship = {
    enable = lib.mkEnableOption "Starship prompt";

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a custom starship.toml. If set, it is symlinked to
        ~/.config/starship.toml via mkOutOfStoreSymlink so edits write back
        to the source. If null, Starship uses its built-in defaults.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
    };

    xdg.configFile = lib.mkIf (cfg.configFile != null) {
      "starship.toml".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
    };
  };
}
