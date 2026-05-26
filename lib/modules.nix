# Module discovery — scan a directory tree for .nix files and import them.
#
# Used by mkDotfilesFlake.nix to auto-load every home-manager module under
# modules/home/ and every nix-darwin module under modules/darwin/ without
# requiring a hand-maintained imports list.
#
# Rules:
#   - Files starting with `_` are private (skipped).
#   - `default.nix` and `flake.nix` are skipped (default.nix is handled at the
#     directory level if you use mapModulesRec').
#   - Only files ending in `.nix` are considered.
#
# Adapted from andreym's dotfiles repo.
{ lib, attrs }:

let
  inherit (builtins) readDir pathExists;
  inherit (lib) hasPrefix hasSuffix nameValuePair removeSuffix;
in rec {
  # Recursively walk `dir` and return a flat list of imported modules.
  #
  # Behaviour:
  #   - For each subdirectory: if it contains default.nix, import that file;
  #     then recurse into the subdirectory looking for more .nix files.
  #   - For each .nix file (excluding default.nix and flake.nix): import it.
  #   - Directories or files starting with `_` are skipped.
  #
  # The flat list shape (vs nested attrset) is what home-manager and nix-darwin
  # want: they take a `modules = [ … ];` list and merge everything via the
  # module system.
  #
  # Example: mapModulesRec' ./modules/home import
  #   modules/home/
  #     default.nix         => imported (as part of `modules/home/` directory walk)
  #     shell/
  #       default.nix       => imported
  #       zsh.nix           => imported
  #       starship.nix      => imported
  #     dev/
  #       claude.nix        => imported
  #       _wip.nix          => skipped (underscore prefix)
  mapModulesRec' = dir: fn:
    let
      recurse = path:
        builtins.concatLists (
          builtins.attrValues (
            attrs.mapFilterAttrs'
              (n: v:
                let fullPath = "${toString path}/${n}"; in
                if v == "directory" && !(hasPrefix "_" n)
                then
                  let dirDefault = "${fullPath}/default.nix"; in
                  nameValuePair n (
                    (if pathExists dirDefault then [ (fn fullPath) ] else [])
                    ++ recurse fullPath
                  )
                else if v == "regular" &&
                        n != "default.nix" &&
                        n != "flake.nix" &&
                        hasSuffix ".nix" n &&
                        !(hasPrefix "_" n)
                then nameValuePair n [ (fn fullPath) ]
                else nameValuePair "" [])
              (n: v: v != [])
              (readDir path)
          )
        );
    in recurse dir;

  # Convenience for host directories: each subdir with a default.nix becomes
  # a named entry. Returns an attrset (so hosts are addressable by name).
  #
  # Accepts either a single dir or a list of dirs (merged with later entries
  # winning on name collision).
  #
  # Example: mapHosts ./hosts =>
  #   { example-mac = <imported>; example-linux = <imported>; }
  #
  # Example: mapHosts [ ./hosts ./private/personal/hosts ./private/work/hosts ]
  #   merges all three.
  mapHosts = dirOrDirs:
    let
      walk = dir:
        attrs.mapFilterAttrs'
          (n: v:
            let path = "${toString dir}/${n}"; in
            if v == "directory" && pathExists "${path}/default.nix"
            then nameValuePair n (import path)
            else nameValuePair "" null)
          (n: v: v != null && !(hasPrefix "_" n))
          (readDir dir);
      dirs =
        if builtins.isList dirOrDirs
        then dirOrDirs
        else [ dirOrDirs ];
      attrsList = map walk (builtins.filter pathExists dirs);
    in
      lib.foldl' (acc: a: acc // a) { } attrsList;
}
