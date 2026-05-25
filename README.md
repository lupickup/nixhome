# nixhome

Composable [nix-darwin](https://github.com/LnL7/nix-darwin) +
[home-manager](https://github.com/nix-community/home-manager) base for layered
private overlays.

## Status

Phase 0 skeleton — not yet usable. The Phase 1 implementation will add:

- `lib/mkDotfilesFlake.nix` — custom flake builder.
- `modules/` — auto-discovered home-manager + nix-darwin modules, each behind
  an `enable` flag.
- Typed `dotfiles.context.*` options replacing the
  isWSL/isRemote/isDarwin/managedHost flag soup.
- Example hosts demonstrating composition.

## Goals

- **Single shared base** for macOS + Linux + WSL.
- **Composable packs** that turn on context-specific config via boolean
  options.
- **Per-host file** as the only deployment-specific entry point.
- **No corporate identifiers** — work-specific identity/hosts live in private
  overlay flakes that import `nixhome` as an input.

## Architecture sketch

Public OSS repo (this one):

- `lib/` — flake builder + module discovery + option helpers.
- `modules/base/` — option schemas (always loaded).
- `modules/home/{shell,dev,platform,…}/<app>.nix` — inert until enabled.
- `modules/darwin/{homebrew,launchd,system-defaults}.nix` — same pattern.
- `hosts/example-*/` — reference hosts for forkers.

Private overlay (separate repo, not this one):

- Own `flake.nix` with `inputs.nixhome.url = "github:tot0/nixhome"`.
- `hosts/<your-machines>/` — dense host files.
- `private/` — identity profiles, work-specific modules, secrets glue.

## Forking

Once Phase 1 lands, the fork path will be:

1. Fork or clone `nixhome`.
2. Create your own private overlay flake that imports it.
3. Define hosts in your overlay.
4. `home-manager switch --flake <your-overlay>#<your-host>` (or
   `darwin-rebuild switch`).

## License

MIT (after Phase 7 OSS audit). Currently a private skeleton.
