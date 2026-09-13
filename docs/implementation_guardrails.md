# Implementation Guardrails

Rules for changing this repo. Follow these phases in order.

## 1. Audit (before writing any Nix)

- Read the module you are changing and every file it touches on disk: symlink targets, reconciled JSON/TOML files, launchd plists, brew bundles.
- Produce an explicit inventory of what the change will write, create, remove, or symlink, and which host profiles it affects. Check `hosts/*.nix` - a module is only live on the hosts that import it.
- If an agent CLI or another tool also writes into a file nix would own, that is a conflict to resolve explicitly (merge-reconcile, not a symlink - see `modules/home/docker.nix`).

## 2. Implement

- Declarative Nix patterns first (`home.file`, `programs.*`, `launchd.agents`). Activation shell only for state nix cannot express, and always through `mkReconcile` (`modules/home/lib/reconcile.nix`) - never a raw string in `home.activation`.
- Every activation script must be idempotent and safe on a machine that never had the artifact: guard with `[ -e ]`/`[ -d ]`, rewrite JSON with `json_edit`, opt out of strict mode per-command with `|| true` only for genuinely best-effort steps.
- Permanent reconciles live with their feature module; one-time migration sweeps go in `modules/home/legacy.nix`; anything meant to be deleted later is its own file marked TEMPORARY.
- Never add `brew uninstall` loops - `cleanup = "zap"` already removes undeclared packages.
- When a `home.file` entry is removed, confirm no stale symlink or empty directory remains at the target path.
- When a structural pattern changes significantly (e.g. a symlink becomes a merge-reconcile, a manual command becomes a launchd agent), propose the approach and get approval before implementing.

## 3. Verify

- `nix fmt`, then `nix flake check --impure --no-build` (evaluates every profile) and the warning grep from AGENTS.md "Commands" - no new warnings beyond the documented `options.json` one.
- Build the home activation package for the affected host so every `mkReconcile` script is shellchecked, not just evaluated.
- Diff every config file the change owns: capture path and content before and after the rebuild. Any unintended change is a blocker.
- The user runs `rebuild` themselves; hand them a checklist of what to confirm afterwards.

## 4. Hand Off

- Update `README.md` (keep it short), `docs/architecture.md`, and `docs/gotchas.md` for any user-facing change: new commands, bootstrap steps, package lists, or gotchas.
- Update `AGENTS.md` if the layout tree, invariants, or reconcile table changed.
