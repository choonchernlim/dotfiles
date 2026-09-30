#!/usr/bin/env bash
# Pulls a checkout, and recovers when the pull fails.
# Called by rebuild.sh and sync-skills.sh, only for a checkout that is on main.
#
#   git-sync.sh <repo-dir> <label>
#
# A pull that conflicts would otherwise abort the whole rebuild until someone
# resolves it by hand. Instead: save everything local (unpushed commits, dirty
# and untracked files, conflicted files) to a rebuild-backup/<timestamp> branch,
# then hard-reset to upstream so the rebuild applies the remote's state.
# A failed fetch (offline, no access) still aborts: there is nothing to reset to.
set -euo pipefail

dir="${1:?usage: git-sync.sh <repo-dir> <label>}"
label="${2:?usage: git-sync.sh <repo-dir> <label>}"

git_() { git -C "$dir" "$@"; }

if out="$(git_ pull --rebase --autostash 2>&1)"; then
  printf '%s\n' "$out"
  exit 0
fi

# Clear any half-finished rebase/merge, including one left by an earlier run.
git_ rebase --abort >/dev/null 2>&1 || true
git_ merge --abort >/dev/null 2>&1 || true

fail() {
  # Not printed on success: its `error:` lines would render as a red failure in
  # the rebuild summary even though the reset below recovers.
  printf '%s\n' "$out" >&2
  echo "error: $label git pull failed - $1 before rebuilding" >&2
  exit 1
}

git_ fetch >/dev/null 2>&1 || fail "fix network/access"
upstream="$(git_ rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" ||
  fail "set an upstream branch"

# commit-tree needs an identity; a fresh machine may not have one configured.
if ! git_ var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
  export GIT_AUTHOR_NAME=rebuild GIT_AUTHOR_EMAIL=rebuild@localhost
  export GIT_COMMITTER_NAME=rebuild GIT_COMMITTER_EMAIL=rebuild@localhost
fi

backup="rebuild-backup/$(date +%Y%m%d-%H%M%S)"
git_ add -A >/dev/null 2>&1 || fail "resolve conflicts"
tree="$(git_ write-tree)" || fail "resolve conflicts"
commit="$(git_ commit-tree "$tree" -p HEAD -m "rebuild backup before reset to $upstream")" ||
  fail "resolve conflicts"
git_ branch "$backup" "$commit" >/dev/null 2>&1 || fail "resolve conflicts"

git_ reset --hard "$upstream" >/dev/null 2>&1 || fail "resolve conflicts"
echo ">> sync $label: pull failed - reset to $upstream, local state saved in branch $backup" >&2
