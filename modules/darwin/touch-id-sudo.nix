# modules/darwin/touch-id-sudo.nix — opt in to TouchID for sudo via
# pam_tid via nix-darwin's security.pam.services.sudo_local.
#
# Inert on managedHost=true so corporate PAM stacks aren't disturbed.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.darwin.touch-id-sudo;
  ctx = config.dotfiles;
in
{
  options.modules.darwin.touch-id-sudo = {
    enable = lib.mkEnableOption "TouchID-for-sudo via PAM";
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin && !ctx.context.managedHost) {
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
