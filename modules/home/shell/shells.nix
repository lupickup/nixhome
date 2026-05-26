# modules/home/shell/shells.nix — symlink the user's shell rc files
# (.profile, .shellenv, .zprofile, .zshenv, .zshrc, .bashrc) from a source
# directory.
#
# Each file is independent (different shells want different things). The
# OSS module deploys NONE by default — forkers point each to their own file:
#
#   modules.home.shell.shells = {
#     enable = true;
#     sourceDir = "''${dotfilesDir}";
#     # Optional per-file overrides:
#     # bashrc = "''${dotfilesDir}/bashrc";  # explicit path
#     # zshenv = null;                       # disable this one
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.shells;

  # For each shell file, prefer the explicit override, fall back to
  # ${sourceDir}/<name>. A null value means "don't symlink this one".
  files = {
    profile  = ".profile";
    shellenv = ".shellenv";
    zprofile = ".zprofile";
    zshenv   = ".zshenv";
    zshrc    = ".zshrc";
    bashrc   = ".bashrc";
  };

  resolveSource = optName: defaultBasename:
    let
      override = cfg.${optName};
    in
      if override == null then null
      else if builtins.isString override || builtins.isPath override
      then toString override
      else if cfg.sourceDir != null
      then "${toString cfg.sourceDir}/${defaultBasename}"
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
        defaults to <sourceDir>/<basename>. Set to null to require explicit
        per-file overrides.
      '';
    };
  } // lib.mapAttrs (optName: basename: lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      Override path for ${basename}. If null and sourceDir is set, falls back
      to <sourceDir>/${basename}. If null and sourceDir is null, ${basename}
      is not deployed.
    '';
  }) (builtins.removeAttrs files [ ]);

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (
      lib.mapAttrsToList (optName: basename:
        let src = resolveSource optName (toString basename);
        in lib.mkIf (src != null) {
          ${basename}.source = config.lib.file.mkOutOfStoreSymlink src;
        }
      ) files
    );
  };
}
