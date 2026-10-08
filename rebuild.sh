#!/bin/sh
# Entry point for `rebuild`: runs the flake-pinned build (bash 5, pinned tools) of
# scripts/rebuild/rebuild.sh. Usage and behaviour are documented there.
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export DOTFILES_DIR
exec nix --option warn-dirty false run --impure "$DOTFILES_DIR#rebuild" -- "$@"
