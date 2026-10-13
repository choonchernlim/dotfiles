#!/usr/bin/env bash
# Copy files listed in the main checkout's .worktreeinclude into a new worktree,
# mirroring `claude -w`: a file is copied only if it matches .worktreeinclude
# AND is gitignored. Runs on herdr's worktree.created event.
set -euo pipefail

# herdr's environment may lack the nix profile, which provides jq.
PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:$PATH"

# The payload shape is not documented, so find the worktree object anywhere in it.
wt=$(jq -r '[.. | objects | select(has("worktree")) | .worktree.path][0] // empty' \
  <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
[ -n "$wt" ] && [ -d "$wt" ] || exit 0

common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
main=$(dirname "$common")
[ "$main" != "$wt" ] || exit 0
[ -f "$main/.worktreeinclude" ] || exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Newline-separated because macOS comm has no -z; filenames with newlines are unsupported.
git -C "$main" ls-files --others --ignored --exclude-from=.worktreeinclude | sort >"$tmp/listed"
git -C "$main" ls-files --others --ignored --exclude-standard | sort >"$tmp/ignored"
comm -12 "$tmp/listed" "$tmp/ignored" >"$tmp/copy"

n=$(wc -l <"$tmp/copy" | tr -d ' ')
if [ "$n" -gt 0 ]; then
  tr '\n' '\0' <"$tmp/copy" | tar -C "$main" --null -T - -cf - | tar -C "$wt" -xpf -
fi
echo "copied $n files from $main into $wt"
