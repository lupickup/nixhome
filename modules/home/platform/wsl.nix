# modules/home/platform/wsl.nix — WSL-only home-manager bits.
#
# Active when dotfiles.context.platform == "wsl". Adds wslu (the WSL
# interop helpers) and sets clipboard backend to clip.exe by default if
# the host hasn't overridden it elsewhere.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.platform.wsl;
  ctx = config.dotfiles.context;
in
{
  options.modules.home.platform.wsl = {
    enable = lib.mkEnableOption "WSL platform glue (wslu, interop helpers)";
  };

  config = lib.mkIf (cfg.enable && ctx.platform == "wsl") {
    # `wslu` was removed from nixpkgs in mid-2025 (project archived). Install
    # the distribution's wslu package via apt if needed.
    home.packages = [ ];
  };
}
