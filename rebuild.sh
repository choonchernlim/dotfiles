#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  local hosts
  hosts="$(cd "$DIR/hosts" && ls -- *.nix 2>/dev/null | sed 's/\.nix$//' | paste -sd '|' -)"
  echo "usage: $(basename "$0") {${hosts:-work|personal}}" >&2
}

profile="${1:-}"
if [ -z "$profile" ] || [ ! -f "$DIR/hosts/$profile.nix" ]; then
  usage
  exit 1
fi

# Sync with the remote before applying so edits pushed from another machine
# are picked up. Only on main; --rebase --autostash keeps the common
# "edit a .nix then rebuild" (dirty tree) flow clean. Abort on real failures.
branch="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
if [ "$branch" = "main" ]; then
  echo ">> syncing repo: git pull --rebase --autostash" >&2
  if ! git -C "$DIR" pull --rebase --autostash; then
    echo "error: git pull failed - resolve conflicts/network before rebuilding" >&2
    exit 1
  fi
else
  echo ">> on branch '${branch:-unknown}' (not main) - skipping git pull" >&2
fi

# home-manager aborts activation ("would be clobbered by backing up") when a stale
# *.hm-bak already occupies the backup path of a file an app has replaced. A .hm-bak is
# displaced garbage by definition - legacy.nix and the per-agent reconciles in
# modules/home/ai/ both already delete them - but those sweeps run after
# checkLinkTargets, too late to unblock it.
echo ">> clearing stale *.hm-bak backups" >&2
find "$HOME" -maxdepth 1 -name '*.hm-bak' -print -exec rm -rf {} + 2>/dev/null || true
for d in "$HOME/.config" "$HOME/.claude" "$HOME/.codex" "$HOME/.copilot" "$HOME/.gemini"; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 3 -name '*.hm-bak' -print -exec rm -rf {} + 2>/dev/null || true
done

ln -sfn "$DIR" ~/.dotfiles
exec sudo --preserve-env=CACHE_PURGE darwin-rebuild switch --impure --flake ~/.dotfiles#"$profile"
