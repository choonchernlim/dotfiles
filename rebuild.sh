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
ln -sfn "$DIR" ~/.dotfiles
exec sudo darwin-rebuild switch --impure --flake ~/.dotfiles#"$profile"
