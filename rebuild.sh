#!/usr/bin/env bash
# Re-applies the flake to this machine.
#   rebuild.sh                  - reuse the profile recorded in /etc/dotfiles-profile
#   rebuild.sh <profile>        - must match the recorded profile
#   rebuild.sh <profile> --force - switch this machine to a different profile
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Written by modules/darwin/system.nix on every switch; absent until the first
# bootstrap. Guards against applying the wrong profile: with homebrew
# cleanup = "zap", that actively uninstalls this machine's packages.
MARKER=/etc/dotfiles-profile

usage() {
  local hosts
  hosts="$(find "$DIR/hosts" -maxdepth 1 -name '*.nix' -exec basename {} .nix \; | sort | paste -sd '|' -)"
  echo "usage: $(basename "$0") [${hosts:-work|personal}] [--force]" >&2
  echo "  no profile:  reuse the one recorded in $MARKER" >&2
  echo "  --force:     allow a profile different from the recorded one" >&2
}

profile=""
force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 1
      ;;
    *) profile="$arg" ;;
  esac
done

current="$(cat "$MARKER" 2>/dev/null || true)"
if [ -z "$profile" ]; then
  if [ -z "$current" ]; then
    echo "error: no profile given and $MARKER is absent (never bootstrapped?) - pass one explicitly" >&2
    usage
    exit 1
  fi
  profile="$current"
fi
if [ ! -f "$DIR/hosts/$profile.nix" ]; then
  echo "error: unknown profile '$profile'" >&2
  usage
  exit 1
fi
if [ -n "$current" ] && [ "$profile" != "$current" ] && [ "$force" -eq 0 ]; then
  echo "error: this machine is recorded as '$current' but '$profile' was requested." >&2
  echo "       applying the wrong profile uninstalls packages (homebrew cleanup = zap)." >&2
  echo "       re-run with --force only if you really mean to switch this machine to '$profile'." >&2
  exit 1
fi
echo ">> profile: $profile" >&2

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
# *.hm-bak already occupies the backup path of a file an app has replaced. The
# per-agent reconciles also delete these, but they run after checkLinkTargets -
# too late to unblock it - so sweep here, before darwin-rebuild.
echo ">> clearing stale *.hm-bak backups" >&2
find "$HOME" -maxdepth 1 -name '*.hm-bak' -print -exec rm -rf {} + 2>/dev/null || true
for d in "$HOME/.config" "$HOME/.claude" "$HOME/.codex" "$HOME/.copilot" "$HOME/.gemini"; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 3 -name '*.hm-bak' -print -exec rm -rf {} + 2>/dev/null || true
done

ln -sfn "$DIR" ~/.dotfiles

# Prompt for the sudo password once up front, then keep the credential cache
# warm in the background: macOS's ~5min sudo timestamp otherwise expires during
# a long step (cask download, agy update) and a later internal sudo call from
# the activation blocks on a TTY prompt.
sudo -v
(
  while true; do
    sudo -n -v
    sleep 50
  done
) &
keepalive_pid=$!
trap 'kill "$keepalive_pid" 2>/dev/null' EXIT

sudo --preserve-env=CACHE_PURGE darwin-rebuild switch --impure --flake ~/.dotfiles#"$profile"
