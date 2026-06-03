# modules/home/skills/default.nix — install AI assistant skill directories
# into Claude Code, Copilot CLI, Codex CLI, and Pi via mkOutOfStoreSymlink
# (or via nix-store path for bundled skills), so the same skill bundle is
# discoverable from each assistant harness.
#
# Targets:
#   ~/.claude/skills/<name>       (Claude Code)
#   ~/.copilot/skills/<name>      (GitHub Copilot CLI)
#   ~/.codex/skills/<name>        (OpenAI Codex CLI)
#   ~/.pi/agent/skills/<name>     (Pi)
#
# Bundled skills can also ship `commands/*.md`. Those are installed as
# namespaced Claude commands and flat Pi prompts, matching those harnesses'
# current command discovery conventions.
#
# nixhome bundles a curated set of generic skills under `_bundled/`. Hosts
# can opt in to any of them via `bundledSkills.<name>.enable = true`, and
# layer their own private skills via `skills = { ... }`. Sources and update
# instructions for bundled skills live in `modules/home/skills/SOURCES.md`.
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

  bundledSkillPath = name: bundledRoot + "/${name}";
  bundledCommandsPath = name: bundledSkillPath name + "/commands";
  bundledHasCommands = name: builtins.pathExists (bundledCommandsPath name);
  bundledCommandFiles = name:
    let entries = builtins.readDir (bundledCommandsPath name);
    in builtins.attrNames (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".md" n) entries);

  enabledBundledSkillEntries =
    lib.filter (skillEntry: skillEntry.value.enable)
      (lib.mapAttrsToList lib.nameValuePair cfg.bundledSkills);
  enabledBundledCommandSkillEntries =
    lib.filter (skillEntry: bundledHasCommands skillEntry.name) enabledBundledSkillEntries;

  piPromptFileNames =
    lib.concatMap (skillEntry: bundledCommandFiles skillEntry.name) enabledBundledCommandSkillEntries;
  duplicatePiPromptFileNames =
    lib.filter
      (fileName:
        (builtins.length (lib.filter (candidate: candidate == fileName) piPromptFileNames)) > 1)
      (lib.unique piPromptFileNames);

  bundledEnabled = name:
    (builtins.hasAttr name cfg.bundledSkills) && cfg.bundledSkills.${name}.enable;

  legacyCleanupPaths =
    (lib.optionals (bundledEnabled "html-effectiveness") [
      "$HOME/.claude/skills/html-effectiveness"
      "$HOME/.copilot/skills/html-effectiveness"
      "$HOME/.codex/skills/html-effectiveness"
      "$HOME/.pi/agent/skills/html-effectiveness"
    ])
    ++ (lib.optionals (bundledEnabled "visual-explainer") ([
      "$HOME/.claude/skills/visual-explainer"
      "$HOME/.copilot/skills/visual-explainer"
      "$HOME/.codex/skills/visual-explainer"
      "$HOME/.pi/agent/skills/visual-explainer"
      "$HOME/.claude/commands/visual-explainer"
    ] ++ (map (fileName: "$HOME/.pi/agent/prompts/${fileName}")
      (lib.optionals (bundledHasCommands "visual-explainer") (bundledCommandFiles "visual-explainer")))));

  # Per-assistant home paths. Adding a new skill target = one line here.
  skillTargets = name: [
    ".claude/skills/${name}"
    ".copilot/skills/${name}"
    ".codex/skills/${name}"
    ".pi/agent/skills/${name}"
  ];

  userSkillFiles = skillEntry:
    let
      skillName = skillEntry.name;
      skillPath = skillEntry.value;
    in
      map (target: {
        ${target}.source =
          config.lib.file.mkOutOfStoreSymlink (toString skillPath);
      }) (skillTargets skillName);

  bundledSkillFiles = skillEntry:
    let
      skillName = skillEntry.name;
      skillCfg = skillEntry.value;
      skillPath = bundledSkillPath skillName;
      commandsPath = bundledCommandsPath skillName;
      commandFiles = lib.optionals (bundledHasCommands skillName) (bundledCommandFiles skillName);
    in
      lib.optionals skillCfg.enable (
        (map (target: {
          ${target}.source = skillPath;
        }) (skillTargets skillName))
        ++ (lib.optionals (commandFiles != [ ]) ([
          {
            ".claude/commands/${skillName}".source = commandsPath;
          }
        ] ++ (map (commandFile: {
          ".pi/agent/prompts/${commandFile}".source = commandsPath + "/${commandFile}";
        }) commandFiles)))
      );
in
{
  options.modules.home.skills = {
    enable = lib.mkEnableOption "user-authored AI assistant skills (Claude + Copilot + Codex + Pi)";

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
        nixhome's bundled set. Each entry is symlinked into each supported
        assistant skill directories.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = duplicatePiPromptFileNames == [ ];
          message = ''
            modules.home.skills: bundled command skills install Pi prompts flat
            under ~/.pi/agent/prompts, but these prompt filenames collide:
            ${lib.concatStringsSep ", " duplicatePiPromptFileNames}
          '';
        }
      ];

      home.file = lib.mkMerge (
        # User-provided skills (out-of-store symlinks — editable in place).
        (lib.concatMap userSkillFiles (lib.mapAttrsToList lib.nameValuePair cfg.skills))
        ++
        # Bundled skills (nix-store paths — read-only but version-pinned).
        (lib.concatMap bundledSkillFiles (lib.mapAttrsToList lib.nameValuePair cfg.bundledSkills))
      );
    }

    (lib.mkIf (legacyCleanupPaths != [ ]) {
      home.activation.cleanupLegacySkillInstalls = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        legacy_paths=(
        ${lib.concatMapStringsSep "\n" (path: "  \"${path}\"") legacyCleanupPaths}
        )

        for path in "''${legacy_paths[@]}"; do
          if [ -e "$path" ] || [ -L "$path" ]; then
            if [ ! -L "$path" ]; then
              rm -rf "$path"
            fi
          fi
        done
      '';
    })
  ]);
}
