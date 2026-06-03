# Bundled skill sources

This file is the source manifest for skills installed by
`modules/home/skills/default.nix`. Keep it updated whenever a bundled skill is
added or refreshed so future agents can audit provenance and update from
upstream without guessing.

## Source inventory

| Skill | Local path | Source | Copied paths | License | Local changes |
|---|---|---|---|---|---|
| `checkpoint` | `_bundled/checkpoint/` | Authored in nixhome | Entire local skill | Project license | No external upstream |
| `html-effectiveness` | `_bundled/html-effectiveness/` | Gallery from `https://github.com/ThariqS/html-effectiveness` at `0e8d447494c81c661f2458b329e076a7ff7d75ec` | Root `*.html` files and `LICENSE` copied into `references/gallery/` | Skill wrapper: MIT; gallery: Apache-2.0 | `SKILL.md` and `references/gallery/INDEX.md` are local wrapper/index docs |
| `visual-explainer` | `_bundled/visual-explainer/` | `https://github.com/nicobailon/visual-explainer` at `8f1d0e38ab0f265632a31d2fd032f7b730c98c15` | `plugins/visual-explainer/` plus root `LICENSE` | MIT | One trailing-whitespace-only cleanup in `references/libraries.md` |

## Update workflow

Prefer updating from a reviewed commit instead of an unpinned branch tip.

### `html-effectiveness`

```sh
cd nixhome
rev=<reviewed-upstream-commit>
tmp=$(mktemp -d)
git clone https://github.com/ThariqS/html-effectiveness.git "$tmp/html-effectiveness"
git -C "$tmp/html-effectiveness" checkout "$rev"

dst=modules/home/skills/_bundled/html-effectiveness/references/gallery
find "$dst" -maxdepth 1 -type f \( -name '*.html' -o -name 'LICENSE' \) -delete
cp "$tmp/html-effectiveness"/*.html "$dst"/
cp "$tmp/html-effectiveness/LICENSE" "$dst"/
```

Then review the diff, update this manifest's commit hash, and keep the local
`SKILL.md` and `INDEX.md` unless the wrapper text also needs to change.

### `visual-explainer`

```sh
cd nixhome
rev=<reviewed-upstream-commit>
tmp=$(mktemp -d)
git clone https://github.com/nicobailon/visual-explainer.git "$tmp/visual-explainer"
git -C "$tmp/visual-explainer" checkout "$rev"

dst=modules/home/skills/_bundled/visual-explainer
rm -rf "$dst"
cp -R "$tmp/visual-explainer/plugins/visual-explainer" "$dst"
cp "$tmp/visual-explainer/LICENSE" "$dst"/
```

Then review the diff, update this manifest's commit hash, and run
`git diff --check` before committing vendored files.
