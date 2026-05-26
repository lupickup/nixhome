# modules/home/shell/ssh.nix — SSH client configuration.
#
# The OSS module owns the SHAPE of programs.ssh (default match-block, agent
# forwarding behaviour, includes list). Identity-specific bits (github.com-<org>
# match blocks, identity files, IdentityAgent paths) come from the host or
# an identity profile via the options below.
#
# On managedHost=true, this whole module is inert (the corporate host's own
# /etc/ssh/ssh_config and ssh helpers are honoured).

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.ssh;
  ctx = config.dotfiles.context;
in
{
  options.modules.home.shell.ssh = {
    enable = lib.mkEnableOption "SSH client configuration";

    forwardAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable ForwardAgent on the wildcard match block.";
    };

    addKeysToAgent = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    identityAgent = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional IdentityAgent socket on the wildcard match block. Common
        value on macOS: 1Password's agent.sock.
      '';
    };

    includes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of Include paths added to ~/.ssh/config.";
    };

    matchBlocks = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = ''
        Extra programs.ssh.matchBlocks entries (e.g. github.com-work,
        github.com-personal). Merged with the default wildcard block.
      '';
    };

    extraConfigFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        {
          "config-extra" = "''${dotfilesDir}/ssh/config-extra";
        }
      '';
      description = ''
        Map of basename (relative to ~/.ssh/) → source path. Each is
        symlinked into ~/.ssh/<basename> via mkOutOfStoreSymlink.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && !ctx.managedHost) {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      includes = cfg.includes;

      matchBlocks = lib.mkMerge [
        {
          "*" = {
            addKeysToAgent = if cfg.addKeysToAgent then "yes" else "no";
            forwardAgent = cfg.forwardAgent;
          } // lib.optionalAttrs (cfg.identityAgent != null) {
            identityAgent = "\"${cfg.identityAgent}\"";
          };
        }
        cfg.matchBlocks
      ];
    };

    home.file = lib.mkMerge (
      lib.mapAttrsToList (basename: src: {
        ".ssh/${basename}".source =
          config.lib.file.mkOutOfStoreSymlink (toString src);
      }) cfg.extraConfigFiles
    );
  };
}
