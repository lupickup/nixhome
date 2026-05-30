# AGENTS.md

Conventions for AI assistants editing nixhome.

This is the **Tier 1 OSS base** — generic flake builder + module library +
bundled default configs. Zero corporate identifiers, zero user emails.
Personal identity (`Lucas Pickup`, gmail) is acceptable in *example* hosts
only because the user has chosen to publish those.

See [README.md](./README.md) for the full architecture overview.

## Discuss before mutating

Investigation is encouraged: inspect files, read docs, and run read-only
checks. Mutation requires agreement first. Do not edit files, apply
configs, commit, push, restart services, or otherwise alter state while
the user is still discussing options unless they explicitly ask for
implementation.

## Hard rules

- **OSS-clean.** No corporate emails (`*@microsoft.com`, etc.), no
  Microsoft hostnames (`lpickup-mn1998`, `work-dev-enc-01`, `*DevBox*`),
  no `linkedin`, no `/mnt/c/...` absolute paths assuming a particular
  Windows setup, no `DEVBOX_*` references outside the dev-box module's
  abstract option name.
- **No agent session references** in comments. No "(per GPT-5 critique)",
  "(via Claude session XYZ)", or similar. Comments must be timeless and
  useful to anyone reading the code cold.
- **Module shape.** Every app module is
  `options.modules.<cat>.<app>.enable = mkEnableOption "…";` plus
  `config = mkIf cfg.enable {…};`. Inert until enabled.
- **No work outside the `mkIf` guard.** Auto-discovery loads every module
  into every config; modules MUST be inert until their `enable` flag fires.
  The one carve-out is the git module's `identityFiles` deployment, which
  is unconditional so writable-symlink hosts can still use identity profiles.
- **Bundled defaults.** Modules that ship default config files / scripts
  use the pattern:
  ```
  useBundled<X> = mkOption { type = bool; default = true; };
  <x>File       = mkOption { type = nullOr path; default = null; };
  ```
  with `configFile != null` always winning, then `useBundled<X>` as
  fallback. Lets users override without breaking the zero-config path.

## Adding things

| You want to … | Goes in … |
|---|---|
| Add a generic OSS module | `modules/home/<cat>/<app>.nix` (PR welcome) |
| Add a bundled config file | `config/<app>/...` + reference as a default in the module |
| Add a bundled helper script | `scripts/<name>` + reference from the module |
| Add a bundled AI skill | `modules/home/skills/_bundled/<name>/` (auto-discovered) |
| Add a new context axis | `modules/base/default.nix` (sparingly!) |
| Add a new example host | `hosts/example-<name>/default.nix` |

## Module conventions

- Options go under `options.modules.<cat>.<app>.*`. Reserved namespaces:
  `home/{shell,dev,platform,skills}/`, `darwin/`, `base/`.
- Use `mkOption { type = ...; default = ...; description = ...; }`. Avoid
  the lib-internal `mkOpt` shorthands in modules — keep modules using
  vanilla nixpkgs lib so they're easy to read.
- Documentation comments at the top of each module: what it does, the
  intended usage shape (with a `modules.home.X.Y = { ... };` example),
  and any caveats.
- When a module reads context, alias once:
  ```
  let
    cfg = config.modules.home.shell.zellij;
    ctx = config.dotfiles.context;
  in
  ```
- Prefer pure config attrs over conditional whole-module imports — keep
  the shape regular so auto-discovery stays predictable.

## File / directory rules

- **Files starting with `_`** are private to the auto-discovery walk and
  skipped (e.g. `_bundled/` content imported via explicit paths).
- **`default.nix`** in a module directory is loaded for the directory's
  semantics (e.g. `modules/base/default.nix`); other `.nix` files in that
  dir are walked individually.
- **Generated artifacts** (`result*`, `.direnv/`) are gitignored.

## Verification

After edits:

```sh
nix flake check --all-systems
nix build .#homeConfigurations.example-linux.activationPackage --no-link
nix build .#homeConfigurations.example-devbox.activationPackage --no-link
# Darwin builds need a Mac (eval works on Linux):
nix eval .#darwinConfigurations.example-mac.config.system.build.toplevel.drvPath
```

## Releasing changes

After a change worth picking up downstream:

1. Commit + push nixhome.
2. In any consuming private overlay: `nix flake update nixhome` →
   commit the bumped `flake.lock`.

If a downstream overlay is using `path:` instead of `github:` for local
iteration, the lock-bump happens automatically on next `nix flake update`.
