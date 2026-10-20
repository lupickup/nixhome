# nixhome's custom Nix library — extends nixpkgs.lib with our helpers.
#
# Exposes:
#   - Reexports of nixpkgs.lib (so you can do `lib.mkIf` etc. as normal).
#   - Our additions: mkOpt, mkBoolOpt, mkEnableOpt, mapModulesRec', mapHosts,
#     mkDotfilesFlake, mkIdentityProfile.
#
# Usage in flake.nix:
#
#   outputs = inputs @ { nixpkgs, ... }:
#     let lib = import ./lib { inherit (nixpkgs) lib; };
#     in lib.mkDotfilesFlake inputs {
#       hosts = lib.mapHosts ./hosts;
#     };
{ lib }:

let
  attrs = import ./attrs.nix { inherit lib; };
  modules = import ./modules.nix { inherit lib attrs; };
  options = import ./options.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  mkDotfilesFlake = import ./mkDotfilesFlake.nix {
    inherit lib;
    modulesLib = modules;
  };
in
  # Our additions live at the top level; nixpkgs.lib is the base.
  lib // attrs // modules // options // identity // {
    inherit mkDotfilesFlake;
    # Namespaced access too, in case of future naming collisions.
    my = {
      inherit attrs modules options identity;
    };
  }
