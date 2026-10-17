{
  description = "nixhome — composable nix-darwin + home-manager base for layered private overlays.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Phase 1: lib + option schemas + example hosts. Phase 2 will populate
  # modules/home/* and modules/darwin/* with the generic app modules.
  outputs = inputs @ { self, nixpkgs, home-manager, darwin, ... }:
    let
      lib = import ./lib { inherit (nixpkgs) lib; };
    in
      (lib.mkDotfilesFlake inputs {
        hosts = lib.mapHosts ./hosts;
        # No aliases yet — the public OSS repo has none.
      }) // {
        # Expose our extended lib so downstream private overlay flakes can:
        #   inputs.nixhome.url = "github:lupickup/nixhome";
        #   lib = inputs.nixhome.lib;
        #   lib.mkDotfilesFlake ...
        inherit lib;

        # Tool builds that keep agents from rewriting shared history; see
        # overlays/agent-guardrails and modules.home.dev.agent-guardrails.
        overlays.agentGuardrails = import ./overlays/agent-guardrails;

        checks = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (system:
          import ./overlays/agent-guardrails/checks.nix {
            inherit nixpkgs home-manager system;
            overlay = self.overlays.agentGuardrails;
            module = ./modules/home/dev/agent-guardrails.nix;
          });
      };
}

