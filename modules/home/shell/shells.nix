# modules/home/shell/shells.nix — symlink the user's shell rc files
# (.profile, .shellenv, .zprofile, .zshenv, .zshrc, .bashrc) from a source
# directory.
#
# Each file is independent (different shells want different things). The
# OSS module deploys NONE by default — forkers point at their source dir:
#
#   modules.home.shell.shells = {
#     enable = true;
#     sourceDir = "''${dotfilesDir}";
#     # Optional per-file overrides:
#     # bashrc = "''${dotfilesDir}/bashrc";  # explicit path
#     # zshenv = null;                       # disable this one
#   };
#
# IMPORTANT: source files in the repo are named WITHOUT a leading dot
# (e.g. `zshrc`, `bashrc`), but deployed to the home directory WITH the dot
# (`~/.zshrc`, `~/.bashrc`). The `files` map below encodes both names per
# entry: { source-basename = "target-basename"; }.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.shells;

  # source basename in the repo  ->  home-relative target basename.
  files = {
    profile  = ".profile";
    shellenv = ".shellenv";
    zprofile = ".zprofile";
    zshenv   = ".zshenv";
    zshrc    = ".zshrc";
    bashrc   = ".bashrc";
  };

  resolveSource = optName: sourceBasename:
    let
      override = cfg.${optName};
    in
      # Explicit per-file override takes precedence when provided.
      if override != null && (builtins.isString override || builtins.isPath override)
      then toString override
      # Otherwise fall back to <sourceDir>/<source-basename> when sourceDir is set.
      else if cfg.sourceDir != null
      then "${toString cfg.sourceDir}/${sourceBasename}"
      # Nothing to deploy for this entry.
      else null;
in
{
  options.modules.home.shell.shells = {
    enable = lib.mkEnableOption "symlinking shell rc files from a source directory";

    sourceDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Default directory to look for shell rc files. Each per-file option
        defaults to <sourceDir>/<source-basename> (the dotless name; the
        deployed home target gets the leading dot). Set to null to require
        explicit per-file overrides.
      '';
    };
  } // lib.mapAttrs (optName: targetBasename: lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      Override path for ${targetBasename}. If null and sourceDir is set,
      falls back to <sourceDir>/${optName} (the source file in the repo is
      ${optName}; deployed to ~/${targetBasename}).
    '';
  }) files;

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (
      lib.mapAttrsToList (sourceBasename: targetBasename:
        let src = resolveSource sourceBasename sourceBasename;
        in lib.mkIf (src != null) {
          ${targetBasename}.source = config.lib.file.mkOutOfStoreSymlink src;
        }
      ) files
    );
  };
}
