# modules/home/shell/zsh.nix — zsh configuration with autosuggestions and
# history-substring-search plugins.
#
# This is the OSS-friendly variant: enable + a few common knobs. The actual
# .zshrc content (aliases, custom functions, prompt integration) is owned by
# the user's repo and gets symlinked via modules.home.shell.shells.

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.shell.zsh;
in
{
  options.modules.home.shell.zsh = {
    enable = lib.mkEnableOption "zsh with package-backed plugins";

    historySize = lib.mkOption {
      type = lib.types.int;
      default = 10000;
      description = "Number of history entries to keep in memory and on disk.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;

      history = {
        size = cfg.historySize;
        save = cfg.historySize;
        ignoreDups = true;
        extended = true;
      };

      initContent = ''
        # Package-backed plugin init. The package outputs live at
        # ${pkgs.zsh-autosuggestions}/share/... and are pulled in via the
        # home.packages list below.
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
        source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh
        bindkey '^[OA' history-substring-search-up
        bindkey '^[[A' history-substring-search-up
        bindkey '^[OB' history-substring-search-down
        bindkey '^[[B' history-substring-search-down
      '';
    };

    home.packages = with pkgs; [
      zsh-autosuggestions
      zsh-history-substring-search
    ];
  };
}
