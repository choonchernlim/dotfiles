# Herdr Worktree Clean

## Shared understanding

Agent runs leave linked worktrees (for example `<repo>/.claude/worktrees/v133` on branch `worktree-v133`) open as herdr workspaces. One command, `herdr-worktree-clean`, removes every linked worktree of the current repo, keeps the main checkout, and never deletes a branch.

Decisions:

- Scope: the repo of the current directory only (what `herdr worktree list` shows).
- Keep: the main checkout (`is_linked_worktree == false`) and every branch. `herdr worktree remove` runs `git worktree remove` and never deletes the branch (herdr v0.9.5 CLI reference); the git fallback behaves the same.
- Dirty worktree (uncommitted or untracked changes): skipped, listed, exit non-zero. `--force` removes it anyway.
- Not open in herdr (`open_workspace_id == null`): removed with `git worktree remove`. Prunable entries (folder gone): `git worktree prune`.
- A real command on PATH (shellchecked `writeShellApplication` in `modules/home/herdr.nix`), not a one-line alias.

## Assumptions

- Decided: the worktree containing `$PWD` is skipped and reported; run from the main checkout to clean everything.
- Confirmed end to end: `herdr worktree remove` also closes that herdr workspace and the agent in it.
- Only the `work` and `personal` hosts get it, as they import `modules/home/herdr.nix`.

## Definition of done

- From the main checkout, `herdr-worktree-clean` removes every clean linked worktree (herdr-open or not), keeps the main checkout and every branch, and skips and lists dirty ones with exit 1.
- `--force` also removes dirty ones; branches are still kept.
- `nix flake check --impure --no-build` and the package build (shellcheck) pass.
- After `rebuild` on work or personal, running it in a repo's main checkout removes `.claude/worktrees/vN`, `worktree-vN` stays in `git branch`, and the main checkout is untouched.
