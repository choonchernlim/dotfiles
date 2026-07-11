#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

usage() { echo "usage: $(basename "$0") {work|personal}" >&2; }

profile="${1:-}"
case "$profile" in
  work|personal) ;;
  *) usage; exit 1 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 0: Xcode Command Line Tools"
# git (needed to clone this repo) and several build steps require the CLT.
# xcode-select --install pops a GUI dialog; wait until the tools appear.
if xcode-select -p >/dev/null 2>&1; then
  echo "    command line tools already installed, skipping"
else
  xcode-select --install
  echo "    complete the Command Line Tools install dialog, then wait..."
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still pinned
# by this repo's flake.lock.
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
NIX_BIN="$(command -v nix)"
sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --impure --flake ~/.dotfiles#"$profile"
# If this still fails with "nix: command not found", open a new terminal
# (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Step 4: install git pre-commit hooks"
# Entering the devShell runs the git-hooks.nix shellHook which writes
# .git/hooks/pre-commit with hermetic Nix store paths (no PATH dependencies).
# || true: a hook-install hiccup must not abort bootstrap; user can re-run
# `nix develop --impure` manually later.
nix develop --impure "$HOME/.dotfiles" -c true || true

echo "==> Done. Use ./rebuild.sh ${profile} for future changes."
