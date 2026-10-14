# modules/darwin/nix-daemon.nix — gate Nix daemon management based on which
# Nix installer is in use.
#
# Determinate Systems' installer manages its own daemon and nix.conf — in
# that case nix-darwin must NOT try to manage them. Traditional installer:
# nix-darwin does the management.

{ config, lib, pkgs, ... }:

let
  ctx = config.dotfiles;
  useDeterminate = ctx.darwin.nixInstaller == "determinate";
in
{
  # No options of its own — reads from dotfiles.darwin.nixInstaller in base.

  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    nix.enable = lib.mkDefault (!useDeterminate);
    nix.settings.experimental-features = lib.mkDefault "nix-command flakes";
    nix.extraOptions = lib.mkIf (!useDeterminate) ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
  };
}
