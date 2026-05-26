# modules/home/platform/darwin.nix — Darwin-only home-manager bits.
#
# Active when dotfiles.context.platform == "darwin". Sets SSH_AUTH_SOCK to
# the 1Password agent socket so GUI tools and shells both see it.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.platform.darwin;
  ctx = config.dotfiles.context;
in
{
  options.modules.home.platform.darwin = {
    enable = lib.mkEnableOption "Darwin platform glue (1Password agent env)";

    onePasswordAgentSock = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional path to 1Password's agent.sock. If set, exported as
        SSH_AUTH_SOCK in shells started via home-manager.

        Typical value:
          /Users/<user>/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock
      '';
    };
  };

  config = lib.mkIf (cfg.enable && ctx.platform == "darwin") {
    home.sessionVariables = lib.mkIf (cfg.onePasswordAgentSock != null) {
      SSH_AUTH_SOCK = cfg.onePasswordAgentSock;
    };
  };
}
