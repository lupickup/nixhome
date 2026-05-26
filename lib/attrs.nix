# Attribute-set utilities used by nixhome's flake builder and module loader.
#
# These are general-purpose attrset operations that aren't in nixpkgs.lib but
# are convenient enough to deserve their own module.
#
# Adapted from andreym's dotfiles repo (MIT licence assumed; original lib is
# small enough to be common idiom).
{ lib }:

with builtins;
with lib;
rec {
  # mapAttrsToList wrapped in a {name, value} pair shape — handy for piping
  # through any/count predicates.
  attrsToList = attrs:
    mapAttrsToList (name: value: { inherit name value; }) attrs;

  # Single-pass map + filter, preserving attr names.
  mapFilterAttrs = f: pred: attrs:
    filterAttrs pred (mapAttrs f attrs);

  # Single-pass map + filter, supports renaming via mapAttrs'.
  mapFilterAttrs' = f: pred: attrs:
    filterAttrs pred (mapAttrs' f attrs);
}
