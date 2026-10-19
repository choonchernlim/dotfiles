#!/usr/bin/env bash
# Fails when evaluating the host profiles prints a warning the rebuild summary
# does not already know (docs/gotchas.md). Module warnings already fail the
# host-<name> flake checks; this catches trace-level ones, which only reach
# stderr. Run from the repo root.
set -euo pipefail

# One evaluation of every profile, so each host's warnings print once.
if ! out="$(nix eval --impure --json .#darwinConfigurations \
  --apply 'builtins.mapAttrs (_: c: c.system.drvPath)' 2>&1 >/dev/null)"; then
  printf 'evaluation failed\n%s\n' "$out" >&2
  exit 1
fi

# The known warnings; keep in step with known_warn in scripts/rebuild/format.sh.
if new="$(grep -i 'warning:' <<<"$out" |
  grep -vE "named 'options\.json'|Git tree '.*' (has uncommitted changes|is dirty)")"; then
  printf 'new evaluation warning(s):\n%s\n' "$new" >&2
  exit 1
fi
