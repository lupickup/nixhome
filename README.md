# nixhome

Composable [nix-darwin](https://github.com/LnL7/nix-darwin) +
[home-manager](https://github.com/nix-community/home-manager) base for
layered private overlays.

`nixhome` is the **OSS-clean Tier 1** of a three-tier dotfiles setup:

```
Tier 1: nixhome (this repo, MIT) — generic flake builder + modules
Tier 2: your private overlay      — your hosts, identity profiles, secrets
Tier 3 (optional): work overlay   — corporate-specific bits, if you have them
```

The idea: ship the boring, generic, reusable pieces here. Keep your
identity, hostnames, work email, signing keys, and corporate
package lists in a private flake that consumes `nixhome` as an input.

## What's in the box

```
flake.nix                Wires lib + auto-loaded modules + example hosts.
flake.lock               Pins nixpkgs-unstable + home-manager + nix-darwin.

lib/
  default.nix            Composes the lib (re-exports nixpkgs.lib + helpers).
  attrs.nix              Attrset helpers (mapFilterAttrs, …).
  modules.nix            mapModulesRec' (recursive .nix discovery) + mapHosts.
  options.nix            mkOpt / mkBoolOpt / mkEnableOpt shorthands.
  mkDotfilesFlake.nix    The flake builder — Darwin (nix-darwin + HM) +
                         standalone HM. Auto-wires HM users on Darwin,
                         hostname aliases, no NixOS.

modules/base/            Loaded for EVERY config. Declares dotfiles.context.*
                         and dotfiles.darwin.* option schemas.

modules/home/            Home-Manager app modules. Each has its own enable.
  shell/{zsh,starship,zellij,shells,git,ssh}.nix
  dev/{claude,codex,opencode,copilot,gsd}.nix
  platform/{linux,wsl,darwin}.nix
  skills/                Generic Claude/Copilot CLI skill installer.

modules/darwin/          nix-darwin system modules.
  {nix-daemon,homebrew,launchd,system-defaults,touch-id-sudo}.nix

hosts/example-{mac,linux}/  Reference hosts. Build them with:
                              nix build .#homeConfigurations.example-linux.activationPackage
                              nix build .#darwinConfigurations.example-mac.system
                            Copy & extend for your own hosts.
```

## Decomposed axes (`dotfiles.context.*`)

Replaces the typical `isWSL` / `isRemote` / `isDarwin` flag soup with a
typed, semantic option set declared in `modules/base/`:

| Option | Values | Notes |
|---|---|---|
| `platform` | `darwin` \| `linux` \| `wsl` | Auto-detects darwin/linux; WSL opts in. |
| `location` | `local` \| `remote` | `remote` = SSH-accessed dev VMs. |
| `identity` | `personal` \| `microsoft` \| `linkedin` | Activates matching profile. |
| `capability` | `minimal-shell` \| `dev` \| `desktop` | Coarse package set. |
| `managedHost` | bool | When true, ssh/PAM/etc. modules go inert. |
| `aiProfile` | `anthropic` \| `copilot` | Routes GSD / Codex / OpenCode. |
| `credentialBackend` | `none` \| `linux-gcm` \| `windows-gcm-wsl` \| `macos-gcm` | Drives git credential.helper. |
| `clipboardBackend` | `wl-clipboard` \| `pbcopy` \| `clip-exe-wsl` \| `xclip` \| `none` | zellij copy_command, etc. |

The `identity` enum lists the three slots upstream uses; you can swap them
for your own labels in your private overlay by overriding the option type.

## Module pattern

Every app module follows this shape:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.modules.home.shell.starship; in
{
  options.modules.home.shell.starship = {
    enable = lib.mkEnableOption "Starship prompt";

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = { enable = true; enableZshIntegration = true; };
    xdg.configFile = lib.mkIf (cfg.configFile != null) {
      "starship.toml".source = config.lib.file.mkOutOfStoreSymlink (toString cfg.configFile);
    };
  };
}
```

**Rule:** every module is inert until its `enable` flag fires. Auto-discovery
loads every module into every config, so modules MUST guard their `config`
attribute with `mkIf cfg.enable {…}`.

## Forking it

1. Create your own private flake somewhere (e.g. `~/dotfiles/`):

   ```nix
   {
     description = "my dotfiles";

     inputs = {
       nixhome.url = "github:lupickup/nixhome";
       nixpkgs.follows = "nixhome/nixpkgs";
       home-manager.follows = "nixhome/home-manager";
       darwin.follows = "nixhome/darwin";
     };

     outputs = inputs @ { nixhome, ... }:
       let lib = nixhome.lib; in
       lib.mkDotfilesFlake inputs {
         hosts = lib.mapHosts ./hosts;
         aliases = {
           "alice@laptop" = "laptop";
         };
       };
   }
   ```

2. Drop a host file at `hosts/<name>/default.nix`:

   ```nix
   { lib, ... }:
   {
     system = "x86_64-linux";
     username = "alice";

     config = { config, pkgs, ... }: {
       dotfiles.context = {
         platform = "linux";
         location = "local";
         identity = "personal";
         capability = "dev";
       };

       modules.home.shell.zsh.enable = true;
       modules.home.shell.starship.enable = true;
       modules.home.dev.claude.enable = true;
     };
   }
   ```

3. Switch:

   ```sh
   home-manager switch --flake ~/dotfiles    # alias resolves automatically
   # or
   home-manager switch --flake ~/dotfiles#alice
   # or for Darwin:
   darwin-rebuild switch --flake ~/dotfiles
   ```

## Adding extra module / host directories

`mkDotfilesFlake` accepts `extraHomeModuleDirs`, `extraDarwinModuleDirs`,
`extraHomeModules`, and `extraDarwinModules`, so you can layer modules from
your private overlay on top of nixhome's base:

```nix
lib.mkDotfilesFlake inputs {
  hosts = lib.mapHosts [ ./hosts ./private/work/hosts ];

  extraHomeModuleDirs = [ ./modules/home ./private/work/modules ];
};
```

## What it deliberately doesn't do

- **NixOS.** None of my own machines are NixOS, so no NixOS path yet.
  Add later if needed.
- **flake-parts / snowfall.** Hand-rolled; small enough to keep direct.
- **Bundle your secrets.** Bring your own `agenix`/`sops-nix`/1Password
  hook; this repo is happy to live alongside any of them.

## Status

In active use as the base of one private dotfiles overlay. The API is
likely to shift before a 1.0 tag — please pin to a commit if you fork.

## License

MIT — see [LICENSE](./LICENSE).
