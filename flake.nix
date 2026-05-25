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

  # Phase 0 skeleton. Phase 1 will populate:
  #   - lib.mkDotfilesFlake (custom flake builder with auto-module-discovery,
  #     Darwin user wiring, hostname aliases, dotfiles.context.* options)
  #   - modules/ tree (base, platform, identity, dev, shell, …)
  #   - hosts/example-{mac,linux}/default.nix reference hosts
  outputs = { self, nixpkgs, home-manager, darwin, ... }: {
    lib = { };

    # Skeleton outputs — replaced in Phase 1.
    homeConfigurations = { };
    darwinConfigurations = { };
  };
}
