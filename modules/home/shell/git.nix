# modules/home/shell/git.nix — Git configuration, generic + identity-driven.
#
# The OSS module owns the SHAPE of programs.git (LFS, signing protocol,
# init.defaultBranch, etc.). Identity-specific bits (user.name, user.email,
# signingKey, signer) come from:
#   1. modules.home.shell.git options (userName, userEmail, signingKey,
#      signingProgram), set by the host or an identity profile module.
#   2. modules.home.shell.git.identityIncludes — list of per-org includes
#      (e.g. github.com-msft url rewrites in microsoft.gitconfig).
#
# Inline-built per-identity gitconfig files (per user decision): the host or
# identity module sets `identityFiles = { personal = "..."; }` and this
# module writes them to `~/<name>.gitconfig`.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.git;
  ctx = config.dotfiles.context;
in
{
  options.modules.home.shell.git = {
    enable = lib.mkEnableOption "Git configuration";

    userName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Top-level git user.name (overridden by per-gitdir includes).";
    };

    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Top-level git user.email (overridden by per-gitdir includes).";
    };

    defaultBranch = lib.mkOption {
      type = lib.types.str;
      default = "main";
    };

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = "Value for core.editor.";
    };

    signing = {
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Top-level signing key. Use the literal SSH public key string on
          agent hosts (so the agent can match it to a private key), or a
          file path on non-agent hosts.
        '';
      };

      program = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path to the SSH signing program. Common values:
            - /Applications/1Password.app/Contents/MacOS/op-ssh-sign  (mac)
            - ~/.local/bin/ssh-sign-wrapper                            (remote)
            - "ssh-keygen"                                              (default)
        '';
      };

      signByDefault = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };

    sshCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional core.sshCommand. Set on remote hosts to route through
        ssh-vscode-wrapper, or on WSL hosts to route through ssh.exe.
        Leave null otherwise.
      '';
    };

    credentialHelper = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional credential.helper string.";
    };

    includes = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        List of programs.git.includes entries. Each is
        { condition, path } or { condition, contents }.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra programs.git.settings (free-form, merged in).";
    };

    identityFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        Map of identity name → gitconfig file body. Each entry is written to
        ~/<name>.gitconfig via home.file, so per-gitdir [include path=]
        directives can reference them.

        Example:
          identityFiles.personal = '''
            [user]
                email = me@example.com
                signingkey = ~/.ssh/personal.pub
            [commit]
                gpgsign = true
          ''';
      '';
    };
  };

  config = lib.mkMerge [
    # Per-identity gitconfig files written into $HOME root. Deployed
    # UNCONDITIONALLY (not gated on enable) so hosts that take a writable-
    # symlink approach to ~/.config/git/config (e.g. for credential-manager
    # write-back) can still benefit from identity profile contributions.
    {
      home.file = lib.mkMerge (
        lib.mapAttrsToList (idName: contents: {
          "${idName}.gitconfig".text = contents;
        }) cfg.identityFiles
      );
    }

    (lib.mkIf cfg.enable {
      programs.git = {
        enable = true;
        lfs.enable = true;

        settings = lib.mkMerge [
          {
            user = lib.mkIf (cfg.userName != "" || cfg.userEmail != "") (
              lib.optionalAttrs (cfg.userName != "") { name = cfg.userName; }
              // lib.optionalAttrs (cfg.userEmail != "") { email = cfg.userEmail; }
            );
            init.defaultBranch = cfg.defaultBranch;
            core.autocrlf = "input";
            core.editor = cfg.editor;
          }
          (lib.optionalAttrs (cfg.sshCommand != null) {
            core.sshCommand = cfg.sshCommand;
          })
          (lib.optionalAttrs (cfg.credentialHelper != null) {
            credential.helper = cfg.credentialHelper;
          })
          (lib.optionalAttrs (cfg.signing.key != null) {
            gpg.format = "ssh";
          })
          (lib.optionalAttrs (cfg.signing.program != null) {
            "gpg \"ssh\"".program = cfg.signing.program;
          })
          cfg.extraSettings
        ];

        signing = lib.mkIf (cfg.signing.key != null) {
          key = cfg.signing.key;
          signByDefault = cfg.signing.signByDefault;
        };

        includes = cfg.includes;
      };
    })
  ];
}
