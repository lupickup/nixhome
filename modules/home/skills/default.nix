# modules/home/skills/default.nix — install AI assistant skill directories
# into Claude Code, Copilot CLI, AND Codex CLI via mkOutOfStoreSymlink
# (or via nix-store path for bundled skills), so the same skill bundle is
# discoverable from any of the three assistants.
#
# Targets:
#   ~/.claude/skills/<name>     (Claude Code)
#   ~/.copilot/skills/<name>    (GitHub Copilot CLI)
#   ~/.codex/skills/<name>      (OpenAI Codex CLI)
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

  # Per-assistant home paths. Adding a new target = one line here.
  skillTargets = name: [
    ".claude/skills/${name}"
    ".copilot/skills/${name}"
    ".codex/skills/${name}"
  ];
in
{
  options.modules.home.skills = {
    enable = lib.mkEnableOption "user-authored AI assistant skills (Claude + Copilot + Codex)";

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
        nixhome's bundled set. Each entry is symlinked into all three
        assistant skill directories.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (
      # User-provided skills (out-of-store symlinks — editable in place).
      (lib.concatMap (skillEntry:
        let
          skillName = skillEntry.name;
          skillPath = skillEntry.value;
        in
          map (target: {
            ${target}.source =
              config.lib.file.mkOutOfStoreSymlink (toString skillPath);
          }) (skillTargets skillName)
      ) (lib.mapAttrsToList lib.nameValuePair cfg.skills))
      ++
      # Bundled skills (nix-store paths — read-only but version-pinned).
      (lib.concatMap (skillEntry:
        let
          skillName = skillEntry.name;
          skillCfg = skillEntry.value;
        in
          map (target:
            lib.mkIf skillCfg.enable {
              ${target}.source = bundledRoot + "/${skillName}";
            }
          ) (skillTargets skillName)
      ) (lib.mapAttrsToList lib.nameValuePair cfg.bundledSkills))
    );
  };
}
