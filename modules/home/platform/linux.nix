# modules/home/platform/linux.nix — Linux-only home-manager bits.
#
# Active when dotfiles.context.platform == "linux" or "wsl". Provides the
# Linux base package set (gcc, htop, fonts) plus optional XDG/fontconfig.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.platform.linux;
  ctx = config.dotfiles.context;
  isLinuxOrWSL = ctx.platform == "linux" || ctx.platform == "wsl";
in
{
  options.modules.home.platform.linux = {
    enable = lib.mkEnableOption "Linux platform glue (packages, fonts, XDG)";

    enableLinuxbrewPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prepend Linuxbrew paths to home.sessionPath.";
    };

    enableDesktopFonts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install nerd-fonts iosevka variants for desktop terminals.";
    };
  };

  config = lib.mkIf (cfg.enable && isLinuxOrWSL) {
    home.packages = with pkgs; [
      gcc
      gnumake
      htop
      lm_sensors
      libsecret
      pkg-config
    ] ++ lib.optionals cfg.enableDesktopFonts [
      nerd-fonts.iosevka
      nerd-fonts.iosevka-term
    ];

    home.sessionPath = lib.mkIf cfg.enableLinuxbrewPath [
      "/home/linuxbrew/.linuxbrew/bin"
      "/home/linuxbrew/.linuxbrew/sbin"
    ];

    xdg = {
      enable = true;
      mimeApps.enable = true;
    };

    fonts.fontconfig.enable = cfg.enableDesktopFonts;
  };
}
