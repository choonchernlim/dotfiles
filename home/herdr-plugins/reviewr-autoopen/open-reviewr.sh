#!/usr/bin/env bash
# Open the reviewr pane in new git-repo workspaces that reviewr's own
# worktree-event auto-open misses; see docs/architecture.md (reviewr-autoopen).
set -euo pipefail

# herdr's environment may lack the nix profile, which provides jq.
PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:$PATH"

herdr=${HERDR_BIN_PATH:-herdr}
ws=$HERDR_WORKSPACE_ID

# A plain workspace's payload has no repo info and no cwd; the invocation context has the cwd.
checkout=$(jq -r '.data.workspace.worktree.checkout_path // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
cwd=${checkout:-$(jq -r '.workspace_cwd // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")}
# Guard the empty string: `git -C ""` means the current directory.
[ -n "$cwd" ] || exit 0
repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Exits the script when the pane list is unreadable: an unknown layout must not
# read as "no reviewr pane" and end in a duplicate.
has_reviewr() {
  local panes
  panes=$("$herdr" pane list --workspace "$ws") || exit 0
  jq -e 'any(.result.panes[]; .label == "reviewr")' <<<"$panes" >/dev/null
}

# A workspace with repo info may get a worktree.* event right after this one,
# and reviewr opens its own pane then (observed in under 1s). Give it 5s, so
# the two never race to open a pane each; the timeout is the gap to fill.
if [ -n "$checkout" ]; then
  for _ in $(seq 20); do
    has_reviewr && exit 0
    sleep 0.25
  done
fi
has_reviewr && exit 0

# Mirrors reviewr's default toggle placement (split, right). The CLI focuses the
# new pane by default; --no-focus keeps the workspace's own pane focused, as
# reviewr's auto-open does. A split takes its workspace from --target-pane and
# rejects --workspace.
"$herdr" plugin pane open \
  --plugin persiyanov.reviewr --entrypoint pane \
  --placement split --direction right --no-focus \
  --target-pane "$HERDR_PANE_ID" --cwd "$repo" >/dev/null
echo "opened reviewr in $ws for $repo"
