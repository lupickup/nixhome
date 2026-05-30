#!/usr/bin/env bash
# install-zellij-plugins.sh: Fetch zellij WASM plugins into ~/.config/zellij/plugins/.
# Idempotent — skips downloads when the pinned version is already on disk.
# Bump the versions in the PLUGINS array below to upgrade.
set -euo pipefail

PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zellij/plugins"
mkdir -p "$PLUGINS_DIR"

# Format: <display-name>|<version>|<owner/repo>|<asset-file>
PLUGINS=(
  "zellij-attention|v0.3.1|KiryuuLight/zellij-attention|zellij-attention.wasm"
  "room|v1.2.1|rvcas/room|room.wasm"
  "zellij-choose-tree|v0.4.2|laperlej/zellij-choose-tree|zellij-choose-tree.wasm"
  "compact-bar|v0.44.3|ivoronin/zellij-tab-bar-indexed|compact-bar.wasm"
)

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found on PATH; cannot fetch zellij plugins." >&2
  exit 1
fi

installed_any=0
for entry in "${PLUGINS[@]}"; do
  IFS='|' read -r name version repo asset <<<"$entry"
  dest="$PLUGINS_DIR/$asset"
  marker="$PLUGINS_DIR/.${asset}.version"
  if [[ -f "$dest" && -f "$marker" && "$(cat "$marker" 2>/dev/null)" == "$version" ]]; then
    echo "[$name] $version already installed"
    continue
  fi
  url="https://github.com/$repo/releases/download/$version/$asset"
  echo "[$name] downloading $version..."
  tmp="$(mktemp --tmpdir "zellij-plugin-XXXXXX")"
  if curl -fsSL -o "$tmp" "$url" && [[ -s "$tmp" ]]; then
    mv "$tmp" "$dest"
    printf '%s\n' "$version" >"$marker"
    echo "[$name] installed $version → $dest"
    installed_any=1
  else
    rm -f "$tmp"
    echo "[$name] download failed; existing $dest (if any) left untouched" >&2
  fi
done

if [[ $installed_any -eq 1 ]]; then
  echo
  echo "Restart any running zellij sessions to pick up plugin changes."
  echo "  zellij list-sessions       # see what's running"
  echo "  zellij kill-all-sessions   # nuke (loses serialized state)"
fi
