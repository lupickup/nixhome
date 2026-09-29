# nixhome

Composable [nix-darwin](https://github.com/LnL7/nix-darwin) +
[home-manager](https://github.com/nix-community/home-manager) base for
layered private overlays.

`nixhome` is the **OSS-clean Tier 1** of a three-tier dotfiles setup:

```
Tier 1: nixhome (this repo, MIT) — generic flake builder + modules + configs
Tier 2: your private overlay      — your hosts, identity, secrets
Tier 3 (optional): work overlay   — corporate-specific bits, if you have them
```

The idea: ship the boring, generic, reusable pieces here — including
opinionated default configs for starship, zellij, copilot CLI, and bundled
AI assistant skills — so a private overlay only needs to declare hosts and
identity. Keep your name, email, signing keys, hostnames, and corporate
package lists in a private flake that consumes `nixhome` as an input.

## What's in the box

```
flake.nix                Wires lib + auto-loaded modules + example hosts.
flake.lock               Pins nixpkgs-unstable + home-manager + nix-darwin.

lib/
  default.nix            Composes the lib (re-exports nixpkgs.lib + helpers).
  attrs.nix              Attrset helpers.
  modules.nix            mapModulesRec' (recursive .nix discovery) + mapHosts.
  options.nix            mkOpt / mkBoolOpt / mkEnableOpt shorthands.
  mkDotfilesFlake.nix    The flake builder — Darwin (nix-darwin + HM) +
                         standalone HM. Auto-wires HM users on Darwin,
                         hostname aliases, no NixOS.

modules/base/            Loaded for EVERY config. Declares dotfiles.context.*
                         and dotfiles.darwin.* option schemas.

modules/home/            Home-Manager app modules. Each has its own enable.
  shell/{zsh,starship,zellij,shells,git,ssh}.nix
  dev/{claude,codex,opencode,copilot,gsd,dev-box}.nix
  platform/{linux,wsl,darwin}.nix
  skills/                Claude+Copilot skill installer. Bundles checkpoint.
  cli-tools.nix          Coming soon (currently in private overlay).

modules/darwin/          nix-darwin system modules.
  {nix-daemon,homebrew,launchd,system-defaults,touch-id-sudo}.nix

config/                  Bundled default configs (used by modules above).
  starship.toml          catppuccin_mocha theme.
  zellij/config.kdl      Vim-friendly keybinds, room/choose-tree/attention plugins.
  ghostty/config         Mac terminal defaults.
  aerospace/             Mac window manager keybinds.
  copilot/copilot-instructions.md  Generic AI agent guidance.

scripts/                 Bundled helper scripts.
  install-zellij-plugins.sh           Pinned 3rd-party WASM plugins.
  ssh-vscode-wrapper, ssh-sign-wrapper, resolve-vscode-ssh-sock
                                       Remote dev-box agent forwarding survival.

hosts/                   Reference hosts. Build them with `nix build`.
  example-linux/         Bare Linux home-configuration skeleton.
  example-mac/           Bare Darwin (nix-darwin) skeleton.
  example-devbox/        Remote dev-box pattern (uses modules.home.dev.dev-box).
```

## Decomposed axes (`dotfiles.context.*`)

Replaces the typical `isWSL` / `isRemote` / `isDarwin` flag soup with a
typed, semantic option set declared in `modules/base/`:

| Option | Values | Notes |
|---|---|---|
| `platform` | `darwin` \| `linux` \| `wsl` | Auto-detects darwin/linux; WSL opts in. |
| `location` | `local` \| `remote` | `remote` = accessed primarily via SSH. |
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

    useBundledConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = { enable = true; enableZshIntegration = true; };
    # …xdg.configFile written from configFile, or bundled, or omitted
  };
}
```

**Rule:** every module is inert until its `enable` flag fires. Auto-discovery
loads every module into every config, so modules MUST guard their `config`
attribute with `mkIf cfg.enable {…}`.

## Forking

### 1. Create your own private overlay flake

Anywhere — e.g. `~/dotfiles/flake.nix`:

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
        "lupickup@laptop" = "laptop";    # `home-manager switch --flake .` resolves
      };
    };
}
```

### 2. Drop a host file at `hosts/<name>/default.nix`

```nix
{ lib, ... }:
{
  system = "x86_64-linux";
  username = "lupickup";

  config = { config, pkgs, ... }: {
    dotfiles.context = {
      platform = "linux";
      location = "local";
      identity = "personal";
      capability = "dev";
    };

    # All bundled configs/scripts come for free.
    modules.home.shell.zsh.enable = true;
    modules.home.shell.starship.enable = true;
    modules.home.shell.zellij.enable = true;
    modules.home.dev.claude.enable = true;
    modules.home.skills = {
      enable = true;
      bundledSkills.checkpoint.enable = true;
      bundledSkills."html-effectiveness".enable = true;
      bundledSkills."visual-explainer".enable = true;
    };
  };
}
```

Bundled skills are installed into Claude Code, GitHub Copilot CLI, Codex CLI,
and Pi skill directories. Bundled skills that include `commands/*.md` also
install namespaced Claude commands under `~/.claude/commands/<skill>/` and Pi
prompts under `~/.pi/agent/prompts/`.

### 3. Switch

```sh
home-manager switch --flake ~/dotfiles    # alias resolves automatically
# or
home-manager switch --flake ~/dotfiles#laptop
# or for Darwin:
darwin-rebuild switch --flake ~/dotfiles
```

That's the entire fork path. No second clone of nixhome is needed — Nix
fetches it on demand from GitHub and pins it in your `flake.lock`.

## Bootstrap on a new machine

**Windows (WSL):** one command from any PowerShell window. It installs the
WSL distro, clones your overlay inside WSL (auth goes through the Windows Git
Credential Manager, so a private repo works without SSH keys), runs its
`./install`, then applies the overlay's `windows/winget.dsc.yaml` if present:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/lupickup/nixhome/main/scripts/bootstrap-windows.ps1))) `
    -DotfilesRepo https://github.com/<you>/dotfiles.git   # add -DryRun to preview
```

It can be rerun. On a brand-new PC, the first run stops after `wsl --install`;
create the Linux user, then run it again.

**macOS / Linux:**

You already have a private overlay flake. You're on a fresh box:

```sh
# 1. Install Nix (if not already)
sh <(curl -L https://nixos.org/nix/install) --daemon

# 2. Clone your private overlay (NOT nixhome — nix will fetch that)
git clone git@github.com:<you>/dotfiles ~/dotfiles

# 3. Apply
nix run home-manager/master -- switch --flake ~/dotfiles#<host>
# or for Mac:
nix run nix-darwin -- switch --flake ~/dotfiles
```

Done. nixhome is now in `/nix/store/...` — Nix fetched the commit pinned by
your overlay's `flake.lock`. You never see the nixhome checkout; it's just
a flake input.

### Iterating on nixhome from that box

If you want to make a nixhome change from the new box (rather than from
your usual workstation):

```sh
# 1. Clone nixhome side-by-side
git clone git@github.com:lupickup/nixhome ~/nixhome

# 2. Override the flake input to your local clone (one-time per checkout)
cd ~/dotfiles
nix flake lock --override-input nixhome path:$HOME/nixhome

# 3. Edit ~/nixhome/... freely; rebuilds pick up changes immediately.
home-manager switch --flake ~/dotfiles

# 4. When you're happy, commit + push nixhome
cd ~/nixhome && git add -A && git commit -m "..." && git push

# 5. Drop the override; pin to the new commit
cd ~/dotfiles && nix flake update nixhome
git add flake.lock && git commit -m "bump nixhome"
```

## Adding extra module / host directories

`mkDotfilesFlake` accepts `extraHomeModuleDirs`, `extraDarwinModuleDirs`,
`extraHomeModules`, and `extraDarwinModules`, so private overlays can layer
modules from their own tree on top of nixhome's base:

```nix
lib.mkDotfilesFlake inputs {
  hosts = lib.mapHosts [ ./hosts ./private/work/hosts ];
  extraHomeModuleDirs = [ ./modules/home ./private/work/modules ];
};
```

## Where to add what

| You want to … | Goes in … |
|---|---|
| Add a generic OSS module (most people would benefit) | `nixhome/modules/home/<cat>/<app>.nix` (PR here) |
| Add a private module (only you / your work need it) | your overlay's `modules/home/...` or `private/<area>/modules/...` |
| Add a new host | your overlay's `hosts/<name>/default.nix` |
| Add a hostname alias | your overlay's `flake.nix` `aliases = { ... }` |
| Add a bundled default config file | `nixhome/config/<app>/` + wire it as a default in the relevant module |
| Add a bundled helper script | `nixhome/scripts/<name>` + reference from the relevant module |
| Add a bundled AI assistant skill | `nixhome/modules/home/skills/_bundled/<name>/` (auto-discovered; optional `commands/*.md` install as Claude commands and Pi prompts; record source in `modules/home/skills/SOURCES.md`) |
| Add a new context axis | `nixhome/modules/base/default.nix` |

## What it deliberately doesn't do

- **NixOS.** None of my own machines are NixOS, so no NixOS path yet.
- **flake-parts / snowfall.** Hand-rolled; small enough to keep direct.
- **Bundle your secrets.** Bring your own `agenix`/`sops-nix`/1Password hook.
- **OS-level provisioning** (Microsoft DevBox image, Ansible roles, MDM
  policies). The `dev-box` module is user-space only — wrappers, agents,
  conventions. Corporate-managed images own the rest.

## Status

In active use as the base of one private dotfiles overlay. The API is
likely to shift before a 1.0 tag — please pin to a commit if you fork.

## License

MIT — see [LICENSE](./LICENSE).
