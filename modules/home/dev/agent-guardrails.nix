# modules/home/dev/agent-guardrails.nix — tool builds that keep agents from
# rewriting shared history.
#
# Applies the overlay in overlays/agent-guardrails to this Home Manager
# configuration, so every package that asks for `git` gets a build that
# refuses `--force`, `--force-with-lease`, `--mirror` and `+<refspec>` pushes
# and never lets a forced update override a non-fast-forward rejection.
# Fast-forward pushes and branch deletion keep working.
#
#   modules.home.dev.agent-guardrails.enable = true;
#
# Caveats:
#   - Standalone Home Manager hosts only. Darwin hosts share nix-darwin's
#     pkgs (`home-manager.useGlobalPkgs`), which disables `nixpkgs.overlays`
#     here; add `nixhome.overlays.agentGuardrails` to the system's
#     `nixpkgs.overlays` instead.
#   - This guards against accidents on the client. Protect important
#     branches on the server too.
#   - The patched git is built locally; binary caches don't carry it.

{ config, lib, ... }:

let
  cfg = config.modules.home.dev.agent-guardrails;
in
{
  options.modules.home.dev.agent-guardrails = {
    enable = lib.mkEnableOption "git that refuses forced pushes, for hosts where agents commit";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ (import ../../../overlays/agent-guardrails) ];
  };
}
