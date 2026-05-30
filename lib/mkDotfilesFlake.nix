# mkDotfilesFlake — flake builder for nixhome.
#
# Tailored for this repo's matrix:
#   - Darwin (nix-darwin + home-manager) AND standalone home-manager.
#   - NO NixOS path (not needed; can be added later).
#   - Auto-wires `home-manager.users.${user}` on Darwin so Darwin host files
#     don't have to re-declare users manually.
#   - Hostname aliases: e.g. `lupickup@laptop` → `laptop`.
#     Home Manager defaults `--flake .#$USER@$HOSTNAME` so aliases let users
#     point cwd-resolved targets at canonical host configs.
#   - Recursively auto-loads modules from `modules/home/` and `modules/darwin/`
#     via lib.mapModulesRec'. Every module is loaded for every config but is
#     inert until enabled via its own `enable` option (rule, not enforced).
#
# Usage (in flake.nix):
#
#   outputs = inputs:
#     let lib = import ./lib { inherit (inputs.nixpkgs) lib; };
#     in lib.mkDotfilesFlake inputs {
#       hosts = lib.mapHosts ./hosts;
#       aliases = {
#         "lupickup@laptop" = "laptop";
#       };
#     };
#
# Host file shape (hosts/<name>/default.nix):
#
#   { lib, ... }:
#   {
#     system = "x86_64-linux";        # required
#     username = "lupickup";              # required
#     homeDirectory = "/home/lupickup";   # optional, defaults to /home/<username>
#     # type = "darwin" | "home";      # optional, auto-detected from system
#
#     config = { config, pkgs, ... }: {
#       dotfiles.context = {
#         platform = "linux";
#         location = "local";
#         identity = "personal";
#         capability = "dev";
#       };
#       # ... enable flags, identity profile selection, etc.
#     };
#   }
#
{ lib, modulesLib }:

inputs: args @ {
  hosts ? { }
  , aliases ? { }
  , overlays ? [ ]
  , extraSpecialArgs ? { }
  # Extra module directories to scan and auto-load. Downstream private overlays
  # use this to layer their own modules on top of the OSS base. Paths are
  # walked with mapModulesRec' just like nixhome's own modules/home/ and
  # modules/darwin/ directories.
  , extraHomeModuleDirs ? [ ]
  , extraDarwinModuleDirs ? [ ]
  # Already-imported module values (functions or attrsets) to also include.
  # Use this for one-off inline modules.
  , extraHomeModules ? [ ]
  , extraDarwinModules ? [ ]
  , ...
}:

let
  inherit (lib) hasSuffix mkDefault genAttrs mapAttrs filterAttrs concatMap;
  inherit (inputs) nixpkgs;

  # Normalise a host's declared config object. Host files can be either an
  # attrset OR a function `{ lib }: <attrset>`.
  normaliseHost = name: host:
    let
      raw = if builtins.isFunction host
            then host { inherit lib; }
            else host;
    in raw // {
      # Defaults
      system = raw.system or "x86_64-linux";
      username = raw.username or name;
      homeDirectory = raw.homeDirectory or
        (if hasSuffix "darwin" (raw.system or "")
         then "/Users/${raw.username or name}"
         else "/home/${raw.username or name}");
      type = raw.type or (
        if hasSuffix "darwin" (raw.system or "")
        then "darwin"
        else "home"
      );
    };

  # Build a nixpkgs instance with our overlays applied. allowUnfree on by
  # default since we use Homebrew casks and a few unfree packages.
  mkPkgs = system: import nixpkgs {
    inherit system overlays;
    config.allowUnfree = true;
  };

  # Auto-load all home-manager modules from ../modules/home/.
  # The walked path is resolved relative to the flake using a `self?` ref
  # passed in via extraSpecialArgs. The caller is expected to pass the flake's
  # `self` so we can find modules/.
  homeModulesPath = ../modules/home;
  darwinModulesPath = ../modules/darwin;
  baseModulesPath = ../modules/base;

  loadHomeModules = builtins.concatLists [
    (if builtins.pathExists baseModulesPath
     then [ (import baseModulesPath) ]
     else [ ])
    (if builtins.pathExists homeModulesPath
     then modulesLib.mapModulesRec' homeModulesPath import
     else [ ])
    (concatMap
      (d: if builtins.pathExists d
          then modulesLib.mapModulesRec' d import
          else [ ])
      extraHomeModuleDirs)
    extraHomeModules
  ];

  loadDarwinModules = builtins.concatLists [
    (if builtins.pathExists baseModulesPath
     then [ (import baseModulesPath) ]
     else [ ])
    (if builtins.pathExists darwinModulesPath
     then modulesLib.mapModulesRec' darwinModulesPath import
     else [ ])
    (concatMap
      (d: if builtins.pathExists d
          then modulesLib.mapModulesRec' d import
          else [ ])
      extraDarwinModuleDirs)
    extraDarwinModules
  ];

  # Build a standalone home-manager configuration (Linux, including WSL).
  mkHomeConfig = name: host:
    let
      h = normaliseHost name host;
      pkgs = mkPkgs h.system;
    in
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = extraSpecialArgs // { inherit inputs; };
        modules = [
          # Base assignments that every home config needs.
          {
            home.username = h.username;
            home.homeDirectory = h.homeDirectory;
            home.stateVersion = lib.mkDefault "24.05";
            programs.home-manager.enable = true;
            nixpkgs.config.allowUnfree = true;
          }
        ]
        ++ loadHomeModules
        ++ (if h ? config then [ h.config ] else [ ]);
      };

  # Build a Darwin (nix-darwin + home-manager) configuration. Auto-wires
  # home-manager.users.${username} so Darwin host files don't have to do it.
  #
  # The host's `config` block is mounted at SYSTEM (nix-darwin) level. Home
  # modules apply to every user via `home-manager.sharedModules`. If the
  # host wants to add user-level overrides, it can do:
  #
  #   home-manager.users.${username} = { ... }: { … };
  #
  # inside its config block.
  mkDarwinConfig = name: host:
    let
      h = normaliseHost name host;
      pkgs = mkPkgs h.system;
    in
      inputs.darwin.lib.darwinSystem {
        inherit (h) system;
        specialArgs = extraSpecialArgs // { inherit inputs; };
        modules = [
          # System-level base.
          {
            nixpkgs.pkgs = mkDefault pkgs;
            networking.hostName = mkDefault name;
          }

          # home-manager as a Darwin module — auto-wires modules for every user
          # via sharedModules. The host's primary user is auto-declared below
          # so even hosts that don't explicitly create the user get the modules.
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = lib.mkDefault "bak";
            home-manager.extraSpecialArgs =
              extraSpecialArgs // { inherit inputs; };
            home-manager.sharedModules = loadHomeModules ++ [
              {
                home.username = lib.mkForce h.username;
                home.homeDirectory = lib.mkForce h.homeDirectory;
                home.stateVersion = lib.mkDefault "24.05";
                programs.home-manager.enable = true;
              }
            ];
            # Auto-declare the host's primary user. Empty config is fine —
            # the sharedModules and stateVersion default get merged in.
            home-manager.users.${h.username} = { ... }: { };
          }

          # Darwin system modules (auto-discovered).
        ] ++ loadDarwinModules
          ++ (if h ? config then [ h.config ] else [ ]);
      };

  # Split hosts by detected type.
  darwinHosts = filterAttrs (n: h: (normaliseHost n h).type == "darwin") hosts;
  homeHosts = filterAttrs (n: h: (normaliseHost n h).type == "home") hosts;

  # Expand aliases into the same-shaped output attrset.
  # aliases = { "user@hostname" = "hostname"; … }
  # For homeConfigurations, the alias name resolves to the same config object
  # as the target host name.
  expandAliases = outputAttrs:
    let
      aliasEntries = mapAttrs
        (_aliasName: targetName:
          outputAttrs.${targetName} or
            (throw "alias '${_aliasName}' -> '${targetName}' but '${targetName}' is not a known host"))
        aliases;
    in outputAttrs // aliasEntries;

in {
  homeConfigurations = expandAliases (mapAttrs mkHomeConfig homeHosts);
  darwinConfigurations = mapAttrs mkDarwinConfig darwinHosts;
}
