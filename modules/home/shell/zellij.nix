# modules/home/shell/zellij.nix — Zellij terminal multiplexer with optional
# custom config and pinned WASM plugins.
#
# The OSS module enables zellij with a default theme and clipboard backend
# derived from dotfiles.context.clipboardBackend. To use a custom config.kdl
# and install third-party plugins:
#
#   modules.home.shell.zellij = {
#     enable = true;
#     configFile = "''${dotfilesDir}/config/zellij/config.kdl";
#     pluginsInstallScript = "''${dotfilesDir}/scripts/install-zellij-plugins.sh";
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.zellij;
  ctx = config.dotfiles.context;

  copyCommand =
    if ctx.clipboardBackend == "pbcopy" then "pbcopy"
    else if ctx.clipboardBackend == "clip-exe-wsl" then "clip.exe"
    else if ctx.clipboardBackend == "wl-clipboard" then "wl-copy"
    else if ctx.clipboardBackend == "xclip" then "xclip -selection clipboard"
    else null;
in
{
  options.modules.home.shell.zellij = {
    enable = lib.mkEnableOption "Zellij terminal multiplexer";

    theme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha";
      description = "Zellij theme name. Must be available in the active config.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a custom zellij config.kdl. Symlinked to
        ~/.config/zellij/config.kdl via mkOutOfStoreSymlink.
      '';
    };

    pluginsInstallScript = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to an executable script that fetches pinned WASM
        plugins into ~/.config/zellij/plugins/. Runs on every
        home-manager switch via an activation hook. Should be idempotent
        (skip downloads when on-disk version matches the pin).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      enableZshIntegration = false;
      settings = {
        theme = cfg.theme;
        default_shell = "zsh";
      } // lib.optionalAttrs (copyCommand != null) {
        copy_command = copyCommand;
      };
    };

    xdg.configFile = lib.mkIf (cfg.configFile != null) {
      "zellij/config.kdl".source =
        config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
    };

    home.activation = lib.mkIf (cfg.pluginsInstallScript != null) {
      installZellijPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v curl >/dev/null 2>&1; then
          bash "${toString cfg.pluginsInstallScript}" || true
        fi
      '';
    };
  };
}
