# modules/home/dev/mbx.nix — mbx (mr-boxington), a shared build cache for Rust.
#
# Installs the `mbx` command. mbx restores matching compiler outputs from one
# store that every checkout shares, and links each checkout's target/ into that
# store under a disk budget (managed target directories, on by default). Build
# through it explicitly:
#
#   mbx build    mbx test --workspace    mbx clippy --workspace --all-targets
#
# With `shim.enable`, plain `cargo` runs through mbx as well: the package's Cargo
# shim (libexec/mbx/cargo) goes ahead of cargo on PATH, so builds started by
# scripts, editors and agents count toward mbx's budget instead of leaving
# unmanaged target/ directories behind. The shim hands commands that build
# nothing (`cargo --version`, `metadata`, `fmt`, `install --list`) straight to
# the real cargo, and `MBX_DISABLE=1` sends everything there. Programs that set
# their own PATH, such as launchd agents, can prepend `shim.directory`. Nix
# builds and `nix develop` shells put their own cargo first and are unaffected.
#
# The module never runs `mbx setup`, so `mbx doctor` keeps reporting "Cargo shim
# is not installed": it looks only for the copy `mbx setup` writes. Check
# `command -v cargo` instead. mbx keeps its settings, such as
# `mbx settings set gc.max_total_size 80GiB`, in its own config file, which
# this module leaves alone. On macOS, scripts/mbx-cache-volume moves mbx's
# cache to a quota-capped APFS volume that Time Machine and Spotlight skip.
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
#     shim.enable = true;
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

    shim = {
      enable = lib.mkEnableOption
        "mbx's Cargo shim ahead of cargo on PATH in login shells, so plain `cargo` commands build through mbx";

      directory = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "${cfg.package}/libexec/mbx";
        defaultText = lib.literalExpression ''"''${config.modules.home.dev.mbx.package}/libexec/mbx"'';
        description = ''
          Directory holding the package's Cargo shim, for programs that set
          their own PATH, such as launchd agents. The shim removes this
          directory from PATH before it looks for the real cargo, so prepend
          this path (or a symlink to it), never a link to the shim placed in
          another directory.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.sessionPath = lib.mkIf cfg.shim.enable [ cfg.shim.directory ];
  };
}
