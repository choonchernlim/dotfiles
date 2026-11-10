# Plan: Herdr Worktree Clean

- [x] Add `herdrWorktreeClean` (`pkgs.writeShellApplication`, runtimeInputs jq) to `modules/home/herdr.nix` and `home.packages`, mirroring `colimaPrune` in `modules/home/colima.nix` → verify: `nix fmt`, `git add`, `nix flake check --impure --no-build` passes, and the package builds (shellcheck)
- [x] Update the herdr.nix header, `README.md` host table, `docs/architecture.md` herdr.nix line, and `docs/gotchas.md` → verify: `nix flake check --impure --no-build` still passes
- [x] E2E on a scratch repo in `/tmp`, never a real repo: two herdr worktrees (one dirty) plus one git-only worktree → verify: clean ones removed, dirty one skipped with exit 1, `--force` removes it with exit 0, every branch still present, main checkout untouched, herdr workspaces closed
- [x] Pre-commit review (`/simplify`, checks, reviewer passes), fix confirmed findings → verify: checks pass, diff shown for approval; no commit, no rebuild

## Files touched

- `modules/home/herdr.nix`
- `README.md`
- `docs/architecture.md`
- `docs/gotchas.md`
