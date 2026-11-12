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
# the real cargo, and `MBX_DISABLE=1` sends everything there. Nix builds and
# `nix develop` shells put their own cargo first and are unaffected.
#
# PATH reaches the shim through ~/.local/libexec/mbx (`shim.directory`), a link
# Home Manager keeps pointing at the current package's libexec/mbx, so the path
# stays the same when mbx changes. Programs that set their own PATH, such as
# launchd agents, prepend it too: their configuration then doesn't change with
# mbx, so a switch that updates mbx doesn't restart them.
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
  shimLink = ".local/libexec/mbx";
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
        default = "${config.home.homeDirectory}/${shimLink}";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/${shimLink}"'';
        description = ''
          Where PATH finds the Cargo shim: a link to the package's
          libexec/mbx that Home Manager keeps current, so the path stays the
          same when mbx changes. Home Manager creates the link only with
          `shim.enable`, so programs that set their own PATH, such as launchd
          agents, should prepend it only when that is set. The shim takes its
          own directory out of PATH, comparing directories with links
          resolved, before it looks for the real cargo, so a link to the
          directory works; a link to the shim file placed in another directory
          makes the shim run itself until mbx gives up.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { home.packages = [ cfg.package ]; }

    (lib.mkIf cfg.shim.enable {
      # One link to the directory, never a directory of links to its files.
      home.file.${shimLink} = {
        source = "${cfg.package}/libexec/mbx";
        recursive = false;
      };
      home.sessionPath = [ cfg.shim.directory ];
    })
  ]);
}
