# modules/darwin/system-defaults.nix — opinionated macOS system.defaults baseline.
#
# Set a few near-universal preferences (dark mode, dock autohide, finder
# pathbar) when enabled. Hosts can override individual values or add more
# via the standard system.defaults attrset; this module is intentionally
# light to avoid being prescriptive.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.darwin.system-defaults;
in
{
  options.modules.darwin.system-defaults = {
    enable = lib.mkEnableOption "opinionated macOS system.defaults baseline";

    darkMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    dockAutohide = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    showAllFileExtensions = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    use24HourTime = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    fastKeyRepeat = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    system.defaults = {
      dock.autohide = cfg.dockAutohide;
      dock.mru-spaces = false;
      finder = {
        _FXShowPosixPathInTitle = true;
        AppleShowAllExtensions = cfg.showAllFileExtensions;
        FXPreferredViewStyle = "clmv";
        ShowPathbar = true;
      };
      loginwindow.GuestEnabled = false;
      NSGlobalDomain = lib.optionalAttrs cfg.use24HourTime {
        AppleICUForce24HourTime = true;
      } // lib.optionalAttrs cfg.darkMode {
        AppleInterfaceStyle = "Dark";
      } // lib.optionalAttrs cfg.fastKeyRepeat {
        KeyRepeat = 2;
      };
    };
  };
}
