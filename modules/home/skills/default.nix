# modules/home/skills/default.nix — install AI assistant skill directories
# into both Claude Code (~/.claude/skills/<name>) and Copilot CLI
# (~/.copilot/skills/<name>) via mkOutOfStoreSymlink, so edits in either
# location write back to the source.
#
# nixhome bundles a curated set of generic skills under `_bundled/`. Hosts
# can opt in to any of them via `bundledSkills.<name>.enable = true`, and
# layer their own private skills via `skills = { ... }`.
#
# Usage in a host:
#
#   modules.home.skills = {
#     enable = true;
#     bundledSkills.checkpoint.enable = true;          # nixhome-shipped
#     skills = {
#       my-private = "${dotfilesDir}/config/skills/my-private";   # overlay
#     };
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.skills;

  bundledRoot = ./_bundled;
  # Auto-discover bundled skill names from the directory.
  bundledNames =
    let entries = builtins.readDir bundledRoot;
    in builtins.attrNames (lib.filterAttrs (n: v: v == "directory" && !(lib.hasPrefix "_" n)) entries);
in
{
  options.modules.home.skills = {
    enable = lib.mkEnableOption "user-authored AI assistant skills (Claude + Copilot)";

    bundledSkills = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.enable = lib.mkEnableOption "this bundled skill";
      });
      default = lib.genAttrs bundledNames (_: { });
      description = ''
        Skills shipped with nixhome. Enable individually:
          modules.home.skills.bundledSkills.checkpoint.enable = true;
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          my-private = "''${dotfilesDir}/config/skills/my-private";
        }
      '';
      description = ''
        Map of skill name → source directory for additional skills outside
        nixhome's bundled set. Each entry is symlinked into both
        ~/.claude/skills/<name> and ~/.copilot/skills/<name>.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (
      # User-provided skills
      (lib.mapAttrsToList (skillName: skillPath: {
        ".claude/skills/${skillName}".source =
          config.lib.file.mkOutOfStoreSymlink (toString skillPath);
        ".copilot/skills/${skillName}".source =
          config.lib.file.mkOutOfStoreSymlink (toString skillPath);
      }) cfg.skills)
      ++
      # Bundled skills (enabled subset)
      (lib.mapAttrsToList (skillName: skillCfg:
        lib.mkIf skillCfg.enable {
          ".claude/skills/${skillName}".source =
            config.lib.file.mkOutOfStoreSymlink (toString (bundledRoot + "/${skillName}"));
          ".copilot/skills/${skillName}".source =
            config.lib.file.mkOutOfStoreSymlink (toString (bundledRoot + "/${skillName}"));
        }
      ) cfg.bundledSkills)
    );
  };
}
