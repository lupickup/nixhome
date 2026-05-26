# modules/home/skills/default.nix — install AI assistant skill directories
# into both Claude Code (~/.claude/skills/<name>) and Copilot CLI
# (~/.copilot/skills/<name>) via mkOutOfStoreSymlink, so edits in either
# location write back to the source.
#
# The skill source is a directory (typically containing SKILL.md +
# optional scripts/ or references/) — directory-level symlink, matching
# the karabiner precedent.
#
# Usage in a host or private overlay:
#
#   modules.home.skills = {
#     enable = true;
#     skills = {
#       checkpoint = "${dotfilesDir}/config/skills/checkpoint";
#       my-other = "${dotfilesDir}/config/skills/my-other";
#     };
#   };
#
# This OSS module deploys an empty skill set by default. Forkers supply
# their own skill directories.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.skills;
in
{
  options.modules.home.skills = {
    enable = lib.mkEnableOption "user-authored AI assistant skills (Claude + Copilot)";

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          checkpoint = "''${dotfilesDir}/config/skills/checkpoint";
        }
      '';
      description = ''
        Map of skill name → source directory. Each entry is symlinked into
        both ~/.claude/skills/<name> and ~/.copilot/skills/<name>.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (
      lib.mapAttrsToList (skillName: skillPath: {
        ".claude/skills/${skillName}".source =
          config.lib.file.mkOutOfStoreSymlink (toString skillPath);
        ".copilot/skills/${skillName}".source =
          config.lib.file.mkOutOfStoreSymlink (toString skillPath);
      }) cfg.skills
    );
  };
}
