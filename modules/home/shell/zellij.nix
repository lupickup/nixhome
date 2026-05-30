# modules/home/shell/zellij.nix — Zellij terminal multiplexer with optional
# custom config and pinned WASM plugins.
#
# nixhome ships an opinionated `config/zellij/config.kdl` and a pinned
# plugin installer script (`scripts/install-zellij-plugins.sh`). Hosts get
# both by default; override `configFile` or `pluginsInstallScript` to use
# your own.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.zellij;
  ctx = config.dotfiles.context;

  bundledConfig = ../../../config/zellij/config.kdl;
  bundledPluginsScript = ../../../scripts/install-zellij-plugins.sh;

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

    useBundledConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use nixhome's bundled config.kdl when `configFile` is null.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a custom zellij config.kdl. Symlinked to
        ~/.config/zellij/config.kdl via mkOutOfStoreSymlink. If null and
        `useBundledConfig` is true, nixhome's bundled config is used.
      '';
    };

    useBundledPlugins = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use nixhome's bundled install-zellij-plugins.sh when `pluginsInstallScript` is null.";
    };

    pluginsInstallScript = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to an executable script that fetches pinned WASM
        plugins into ~/.config/zellij/plugins/. Runs on every
        home-manager switch via an activation hook. Should be idempotent.
        If null and `useBundledPlugins` is true, nixhome's bundled script
        is used (matches the plugin set assumed by the bundled config.kdl).
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

    xdg.configFile = lib.mkMerge [
      (lib.mkIf (cfg.configFile != null) {
        "zellij/config.kdl".source =
          config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
      })
      (lib.mkIf (cfg.configFile == null && cfg.useBundledConfig) {
        "zellij/config.kdl".source = bundledConfig;
      })
    ];

    home.activation = let
      script =
        if cfg.pluginsInstallScript != null then toString cfg.pluginsInstallScript
        else if cfg.useBundledPlugins then toString bundledPluginsScript
        else null;
    in lib.mkIf (script != null) {
      installZellijPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v curl >/dev/null 2>&1; then
          bash "${script}" || true
        fi
      '';
    };
  };
}
