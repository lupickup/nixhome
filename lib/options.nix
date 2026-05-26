# Option-declaration shorthand helpers.
#
# Reduces the boilerplate of declaring `options.modules.<cat>.<app>.enable`
# for every app module from 5 lines to 1.
#
# Adapted from andreym's dotfiles repo.
{ lib }:

let
  inherit (lib) mkOption types;
in rec {
  # mkOpt type default  →  mkOption { type; default; }
  mkOpt = type: default:
    mkOption { inherit type default; };

  # mkOpt' type default description  →  with description.
  mkOpt' = type: default: description:
    mkOption { inherit type default description; };

  # Bool option with explicit default. Used for non-enable bool flags.
  mkBoolOpt = default:
    mkOption {
      inherit default;
      type = types.bool;
      example = true;
    };

  # Standard "enable this thing" bool option, default false.
  # Use this in every app module: every module ships disabled.
  #
  # Example:
  #   options.modules.shell.git.enable = mkEnableOpt "Git configuration";
  mkEnableOpt = description:
    mkOption {
      inherit description;
      type = types.bool;
      default = false;
      example = true;
    };
}
