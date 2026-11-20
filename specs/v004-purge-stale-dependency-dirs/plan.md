# v004 Plan

- [x] Record the spec and plan pair → verify: both files exist and `refs/grill-me/v4` is reserved
- [x] Remove the free-space gate in `cache-purge.sh` (constant, `--auto` df block, `--help`, header) and update the `default.nix` header comment → verify: `cache-purge --help` no longer mentions the gate
- [x] Add the dependency scan to `scan_dev_tree`: a dep-name branch in the find, plus `has_manifest`, `project_idle`, `project_root`, `is_dep_dir`, a shared `record_stale`, and a `consider` that takes a staleness test → verify: a dry run on the real `~/Developer` lists dep dirs as STALE, active or skip, and the STALE total is near 35 GB minus no-manifest dirs
- [x] Gate npm, pip3, yarn, bun and go GC on `is_stale "$dir"` and log `GC skip` → verify: the dry run labels each tool `GC` or `GC skip`
- [x] Fake-HOME fixture run with four projects: stale with manifest, stale with a fresh file, stale `.venv` without manifest, stale `.venv` with `uv.lock`, then `--apply` and `--auto` → verify: only the stale-with-manifest dirs are removed and the summary counts 2
- [x] Update `docs/architecture.md`, `docs/gotchas.md` and `README.md` → verify: `grep -rn "100G" docs README.md modules` returns nothing
- [x] Run `nix fmt`, `statix check .`, `deadnix --fail .`, `nix flake check --impure --no-build`, the `activation` and `rebuild-format` builds and `scripts/check-warnings.sh` → verify: all green
- [x] Pre-commit review: `/simplify`, then the cohesion and bug passes; show the diff for approval → verify: findings fixed or listed

## Files touched
- `modules/home/cachepurge/cache-purge.sh`: header, constants, `scan_dev_tree`, `DEP_DIRS`/`DEP_FIND`, new functions, `run_tool_gc`, `--help`, the gate block
- `modules/home/cachepurge/default.nix`: header comment
- `docs/architecture.md`, `docs/gotchas.md`, `README.md`
- `specs/v004-purge-stale-dependency-dirs/{spec,plan}.md` (new)
