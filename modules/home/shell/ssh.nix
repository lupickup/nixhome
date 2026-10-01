# modules/home/shell/ssh.nix — SSH client configuration.
#
# The OSS module owns the SHAPE of programs.ssh (default match-block, agent
# forwarding behaviour, includes list). Identity-specific bits (github.com-<org>
# match blocks, identity files, IdentityAgent paths) come from the host or
# an identity profile via the options below.
#
# modules.home.shell.ssh.settings uses OpenSSH directive names, for example:
#   settings."git.example.org" = { User = "git"; IdentityFile = "~/.ssh/git"; };
# The deprecated matchBlocks option retains Home Manager's legacy field names.
#
# On managedHost=true, this whole module is inert (the corporate host's own
# /etc/ssh/ssh_config and ssh helpers are honoured).

{ config, lib, options, ... }:

let
  cfg = config.modules.home.shell.ssh;
  ctx = config.dotfiles.context;
  hasLegacyBlocks = cfg.matchBlocks != { };
  wildcardSettings = {
    AddKeysToAgent = if cfg.addKeysToAgent then "yes" else "no";
    ForwardAgent = cfg.forwardAgent;
  } // lib.optionalAttrs (cfg.identityAgent != null) {
    IdentityAgent = "\"${cfg.identityAgent}\"";
  };
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

    settings = lib.mkOption {
      type = options.programs.ssh.settings.type;
      default = { };
      description = ''
        Extra programs.ssh.settings blocks using OpenSSH directive names
        (HostName, User, IdentityFile, ProxyCommand, etc.). Bare attribute
        names become Host patterns; literal Host/Match headers and
        lib.hm.dag ordering are supported. Includes precede all blocks,
        and the default "*" block is emitted last.
      '';
    };

    matchBlocks = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      visible = false;
      description = ''
        Deprecated legacy SSH blocks. Use settings with OpenSSH directive
        names instead. Legacy fields, extraOptions and DAG ordering are
        preserved by Home Manager's matchBlocks compatibility converter.
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
    warnings = lib.optional hasLegacyBlocks ''
      modules.home.shell.ssh.matchBlocks is deprecated. Use
      modules.home.shell.ssh.settings with OpenSSH directive names, and
      move extraOptions directives directly into each settings block.
    '';

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      includes = cfg.includes;

      settings = lib.mkMerge [
        (lib.mkIf (!hasLegacyBlocks) { "*" = wildcardSettings; })
        (lib.mkAliasDefinitions options.modules.home.shell.ssh.settings)
      ];

      # A plain rename cannot translate legacy field names or extraOptions.
      # Merge defaults here so legacy mkForce overrides survive conversion.
      matchBlocks = lib.mkIf hasLegacyBlocks (lib.mkMerge [
        {
          "*" = {
            addKeysToAgent = wildcardSettings.AddKeysToAgent;
            forwardAgent = wildcardSettings.ForwardAgent;
          } // lib.optionalAttrs (cfg.identityAgent != null) {
            identityAgent = wildcardSettings.IdentityAgent;
          };
        }
        cfg.matchBlocks
      ]);
    };

    home.file = lib.mkMerge (
      lib.mapAttrsToList (basename: src: {
        ".ssh/${basename}".source =
          config.lib.file.mkOutOfStoreSymlink (toString src);
      }) cfg.extraConfigFiles
    );
  };
}
