#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $(basename "$0") {work|personal}" >&2; }

profile="${1:-}"
case "$profile" in
  work|personal) ;;
  *) usage; exit 1 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
exec sudo darwin-rebuild switch --impure --flake ~/.dotfiles#"$profile"
