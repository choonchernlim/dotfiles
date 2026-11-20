# v004 Purge stale dependency dirs

## Shared understanding
`cache-purge` prunes at `node_modules`, `.venv` and `venv`, so those dirs are never reclaimed. They hold 38.2 GB of the 52.1 GB in `~/Developer` (117 dirs), and about 35 GB of that sits in projects idle for 30+ days. The pass also runs on rebuild only when free space is under 100G. Decisions: delete a dep dir when its project (the enclosing git repo below ~/Developer, else the folder holding it) has had no modified file for `STALE_DAYS` (14) and a manifest sits beside it; remove the free-space gate so every rebuild runs the pass; run the wipe-everything tool GCs (npm, pip3, yarn, bun, go) only when their cache has been idle for 14 days, while uv and pnpm keep pruning every rebuild.

## Assumptions
- Confirmed: the project is the folder holding the dep dir, widened in review to the enclosing git repo so a monorepo package is not judged alone; a fresh install (dep dir's top level changed) counts as a touch.
- Confirmed: one cutoff, 14 days, for everything.
- Confirmed: dep dirs without a manifest (`package.json`, or `pyproject.toml`/`requirements*.txt`/`setup.py`/`Pipfile`/`uv.lock`) are skipped and logged, never deleted.
- Confirmed: built here on `main`, no commit until the diff is approved.
- Unconfirmed: nested dep dirs inside a pruned dep dir are never visited; symlinked dep dirs are not followed.

## Definition of done
- A rebuild deletes `node_modules`/`.venv`/`venv` in `~/Developer` when the project is idle 14+ days and a manifest exists, regardless of free space; dirs without a manifest stay.
- npm, pip3, yarn, bun and go caches are wiped only after 14 idle days; uv and pnpm prune every rebuild.
- A fake-HOME fixture run removes exactly the expected dirs and keeps the rest.
- `nix fmt`, `statix check .`, `deadnix --fail .`, `nix flake check --impure --no-build`, the `activation` and `rebuild-format` checks and `scripts/check-warnings.sh` pass.
- Docs (`docs/architecture.md`, `docs/gotchas.md`, `README.md`) match the code and no longer mention the 100G gate.
