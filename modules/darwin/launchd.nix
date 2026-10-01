# modules/darwin/launchd.nix — accept a free-form attrset of launchd user agents.
#
# Hosts/private overlays compose their agent set; this module just lets them
# enable that and exposes a stable option path. nix-darwin's launchd.user.agents
# is the underlying primitive.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.darwin.launchd;
in
{
  options.modules.darwin.launchd = {
    enable = lib.mkEnableOption "launchd user agents (passthrough to nix-darwin)";

    agents = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      example = lib.literalExpression ''
        {
          onepassword-ssh-auth-sock = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/launchctl" "setenv" "SSH_AUTH_SOCK"
                "/Users/me/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
              ];
              RunAtLoad = true;
            };
          };
        }
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    launchd.user.agents = cfg.agents;
  };
}
