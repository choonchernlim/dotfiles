#!/usr/bin/env bash
# Re-applies the flake to this machine.
#   rebuild.sh                  - reuse the profile recorded in /etc/dotfiles-profile
#   rebuild.sh <profile>        - must match the recorded profile
#   rebuild.sh <profile> --force - switch this machine to a different profile
#   rebuild.sh -v|--verbose     - print the raw stream instead of the grouped summary
#
# Two processes share this file. The one you launch (the "outer" run) re-executes
# itself as the "inner" run (REBUILD_INNER=1), which does the actual work and
# prints a raw stream. The outer run tees that stream to a log and pipes it
# through scripts/rebuild-format.sh. Re-exec instead of piping a function keeps
# `set -e` and the EXIT trap behaving as in any ordinary process - bash 3.2 (the
# macOS /bin/bash) does not fire an EXIT trap set inside a pipeline member.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Written by modules/darwin/system.nix on every switch; absent until the first
# bootstrap. Guards against applying the wrong profile: with homebrew
# cleanup = "zap", that actively uninstalls this machine's packages.
MARKER=/etc/dotfiles-profile

usage() {
  local hosts
  hosts="$(find "$DIR/hosts" -maxdepth 1 -name '*.nix' -exec basename {} .nix \; | sort | paste -sd '|' -)"
  echo "usage: $(basename "$0") [${hosts:-work|personal}] [--force] [--verbose]" >&2
  echo "  no profile:  reuse the one recorded in $MARKER" >&2
  echo "  --force:     allow a profile different from the recorded one" >&2
  echo "  --verbose:   print the raw stream instead of the grouped summary" >&2
}

profile=""
force=0
verbose=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -v | --verbose) verbose=1 ;;
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

# ---- outer run: log + present ------------------------------------------------
if [ "${REBUILD_INNER:-0}" != 1 ]; then
  logdir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
  mkdir -p "$logdir"
  log="$logdir/rebuild-$(date +%Y%m%d-%H%M%S).log"
  # Keep the newest 10 runs (this run's log is created below, so keep 9 old ones);
  # the timestamped names sort by age.
  find "$logdir" -maxdepth 1 -name 'rebuild-*.log' | sort -r | tail -n +10 | while IFS= read -r old; do rm -f -- "$old"; done
  phase_file="$(mktemp)"

  fmt_dur() {
    if [ "$1" -ge 60 ]; then printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi
  }
  present() {
    if [ "$verbose" -eq 1 ]; then
      cat
    else
      # The formatter records the section it was in, so a failure can name its phase.
      REBUILD_PHASE_FILE="$phase_file" "$BASH" "$DIR/scripts/rebuild-format.sh"
    fi
  }

  # errexit off only around the pipeline, so the inner run's exit code is read
  # from PIPESTATUS instead of aborting this script.
  SECONDS=0
  set +e
  REBUILD_INNER=1 "$BASH" "$DIR/$(basename "${BASH_SOURCE[0]}")" "$@" 2>&1 | tee "$log" | present
  rc=${PIPESTATUS[0]}
  set -e

  case "$log" in
    "$HOME"/*) shown_log="~${log#"$HOME"}" ;;
    *) shown_log="$log" ;;
  esac
  phase="$(cat "$phase_file" 2>/dev/null || true)"
  rm -f "$phase_file"
  echo ""
  if [ "$rc" -eq 0 ]; then
    echo "✅ done in $(fmt_dur "$SECONDS")  ·  log: $shown_log"
  else
    echo "❌ ${phase:-rebuild} failed (exit $rc) after $(fmt_dur "$SECONDS")"
    echo "   last 40 raw lines:"
    tail -n 40 "$log" | sed 's/^/   /'
    echo "   full log: $shown_log"
  fi
  exit "$rc"
fi

# ---- inner run: the actual work, raw output -----------------------------------
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

# Skills live in their own repo; this is what makes `rebuild` pick up the latest.
"$DIR/sync-skills.sh"

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
# stdio detached: this loop would otherwise inherit the pipe to the outer run and
# hold it open after the switch ends, so the formatter would never see EOF.
(
  while true; do
    sudo -n -v
    sleep 50
  done
) >/dev/null 2>&1 &
keepalive_pid=$!
trap 'kill "$keepalive_pid" 2>/dev/null' EXIT

sudo --preserve-env=CACHE_PURGE darwin-rebuild switch --impure --flake ~/.dotfiles#"$profile"
