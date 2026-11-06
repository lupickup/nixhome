# modules/home/dev/mbx.nix — mbx (mr-boxington), a shared build cache for Rust.
#
# Installs the `mbx` command and nothing else. mbx restores matching compiler
# outputs from one store that every checkout shares, and links each checkout's
# target/ into that store under a disk budget (managed target directories, on
# by default). Build through it explicitly:
#
#   mbx build    mbx test --workspace    mbx clippy --workspace --all-targets
#
# Plain `cargo` keeps running without mbx: the package's Cargo shim stays in
# libexec/, off PATH, and this module never runs `mbx setup`. mbx keeps its
# settings, such as `mbx settings set gc.max_total_size 80GiB`, in its own
# config file, which this module leaves alone.
#
# nixhome takes no flake inputs, so the host passes the package from mbx's
# flake (https://github.com/jdx/mr-boxington):
#
#   inputs.mbx = {
#     url = "github:jdx/mr-boxington/v1.29.2";
#     inputs.nixpkgs.follows = "nixpkgs";
#   };
#
#   modules.home.dev.mbx = {
#     enable = true;
#     package = inputs.mbx.packages.${pkgs.stdenv.hostPlatform.system}.mbx;
#   };

{ config, lib, ... }:

let
  cfg = config.modules.home.dev.mbx;
in
{
  options.modules.home.dev.mbx = {
    enable = lib.mkEnableOption "mbx (mr-boxington), a shared, self-pruning build cache for Rust";

    package = lib.mkOption {
      type = lib.types.package;
      example = lib.literalExpression "inputs.mbx.packages.\${pkgs.stdenv.hostPlatform.system}.mbx";
      description = "The mbx package, from mbx's flake.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
