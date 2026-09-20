#!/usr/bin/env bash
# Clones or updates the skills repo and points ~/.dotfiles-skills at it.
# Called by rebuild.sh and bootstrap.sh before the switch; safe to run by hand.
#
# Skills live in their own repo, checked out beside this one and served live as
# the ~/.agents/skills hub (modules/home/ai/default.nix). This runs here, in the
# user's shell, rather than in nix activation: the repo is cloned over whatever
# auth this machine uses for git, and the hermetic activation PATH has no ssh.
#
#   SKILLS_REPO  - clone URL; defaults to this repo's origin with the last path
#                  segment swapped for skills.git, so the protocol that fetched
#                  the dotfiles (ssh or https) fetches the skills too
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_DIR="$(dirname "$DIR")/skills"

if [ ! -d "$SKILLS_DIR/.git" ]; then
  if [ -e "$SKILLS_DIR" ]; then
    echo "error: $SKILLS_DIR exists but is not a git checkout - move it aside and re-run" >&2
    exit 1
  fi
  url="${SKILLS_REPO:-}"
  if [ -z "$url" ]; then
    origin="$(git -C "$DIR" remote get-url origin)"
    url="${origin%/*}/skills.git"
  fi
  echo ">> cloning skills repo: $url -> $SKILLS_DIR" >&2
  # No fallback: without the checkout the ~/.agents/skills hub dangles and every
  # agent silently loses its skills.
  if ! git clone "$url" "$SKILLS_DIR"; then
    echo "error: cloning the skills repo failed - fix access/network, or set SKILLS_REPO" >&2
    exit 1
  fi
else
  # Same policy as the dotfiles pull in rebuild.sh: only on main, so a skill
  # being developed on a branch is never rebased underneath its author.
  branch="$(git -C "$SKILLS_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ "$branch" = "main" ]; then
    echo ">> syncing skills repo: git pull --rebase --autostash" >&2
    if ! git -C "$SKILLS_DIR" pull --rebase --autostash; then
      echo "error: skills repo git pull failed - resolve conflicts/network before rebuilding" >&2
      exit 1
    fi
  else
    echo ">> skills repo on branch '${branch:-unknown}' (not main) - skipping git pull" >&2
  fi
fi

# The home modules resolve the hub through this link, the same way they resolve
# everything else through ~/.dotfiles.
ln -sfn "$SKILLS_DIR" ~/.dotfiles-skills
