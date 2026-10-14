# modules/darwin/codex.nix — system-level Codex policy in
# /etc/codex/requirements.toml.
#
# Codex (CLI and desktop app) reads admin requirements from
# /etc/codex/requirements.toml. Users, the app, and config.toml can't relax
# them, so this is the place to lock down what local Codex threads may touch
# while $CODEX_HOME/config.toml stays app-owned and writable.
#
#   modules.darwin.codex = {
#     enable = true;
#     # Client-only install: drive remote-control workers, but local threads
#     # get no home, workspace, /tmp, or network access and no local tools
#     # that reach apps, browsers, or MCP servers.
#     remoteClient.enable = true;
#     # Extra requirements merge on top (see Codex's requirements.toml docs).
#     requirements.allowed_web_search_modes = [ "cached" ];
#   };
#
# Profiles defined here must not reuse a profile name from a loaded
# config.toml; Codex rejects the duplicate.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.darwin.codex;
  toml = pkgs.formats.toml { };
  profile = cfg.remoteClient.profileName;
in
{
  options.modules.darwin.codex = {
    enable = lib.mkEnableOption "system Codex requirements (/etc/codex/requirements.toml)";

    requirements = lib.mkOption {
      type = toml.type;
      default = { };
      example = lib.literalExpression ''
        {
          allowed_approval_policies = [ "on-request" ];
          allowed_web_search_modes = [ "cached" ];
        }
      '';
      description = ''
        Contents of /etc/codex/requirements.toml as a Nix attrset. Presets
        such as `remoteClient` contribute defaults that these values
        override.
      '';
    };

    remoteClient = {
      enable = lib.mkEnableOption ''
        a client-only lockdown: Codex may drive remote-control workers, but
        local threads run under a permission profile with minimal runtime
        reads only, never escalate, and can't use the shell, image viewing,
        Computer Use, browser control, local automations, or MCP servers
      '';

      profileName = lib.mkOption {
        type = lib.types.str;
        default = "locked-remote-client";
        description = ''
          Name of the managed permission profile. Must not match a profile
          defined in the user's config.toml.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.remoteClient.enable {
      modules.darwin.codex.requirements = lib.mapAttrsRecursive (_: lib.mkDefault) {
        default_permissions = profile;
        allowed_permission_profiles = { ${profile} = true; };
        allowed_approval_policies = [ "never" ];
        allowed_approvals_reviewers = [ "user" ];
        allow_login_shell = false;
        allow_browser_and_computer_use = false;

        permissions.${profile} = {
          description = "Remote-control client: minimal runtime reads only; no home, workspace, /tmp, or network access.";
          filesystem = {
            ":minimal" = "read";
            "~" = "deny";
            ":slash_tmp" = "deny";
            ":workspace_roots"."." = "deny";
          };
          network.enabled = false;
        };

        features = {
          shell_tool = false;
          view_image = false;
          computer_use = false;
          browser_use = false;
          browser_use_external = false;
          browser_use_full_cdp_access = false;
          in_app_local_automation = false;
          skill_mcp_dependency_install = false;
        };

        computer_use.allow_locked_computer_use = false;

        # Empty allowlists: no configured or plugin-bundled MCP server starts.
        mcp_servers = { };
        plugins = { };
      };
    })

    {
      environment.etc."codex/requirements.toml".source =
        toml.generate "codex-requirements.toml" cfg.requirements;
    }
  ]);
}
