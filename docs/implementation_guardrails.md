<!--
Purpose: Defines the ordered workflow and safety checks for changing this repository.
Type: how-to
-->

# Implementation Guardrails

Audience: maintainers preparing and verifying a dotfiles change.

Rules for changing this repository. Follow these phases in order.

## Audit Before Writing Nix

- Read the module and every file it touches, including symlink targets,
  reconciled data, launchd plists, and Homebrew bundles.
- Inventory every write, creation, removal, and symlink.
  - Name each affected host profile from `hosts/*.nix`.
- Resolve shared ownership when another tool writes a Nix-managed file.
  - Use the merge-reconcile pattern from `modules/home/docker.nix`.

## Implement

- Prefer declarative options such as `home.file`, `programs.*`, and
  `launchd.agents`.
- Use `mkReconcile` only for state that Nix cannot express.
- Make each activation safe when the artifact never existed.
  - Guard paths, use `json_edit`, and limit `|| true` to best-effort work.
- Follow the placement rules in the
  [architecture guide](architecture.md#repository-layout).
- Never add `brew uninstall` loops - `cleanup = "zap"` already removes undeclared packages.
- When a `home.file` entry is removed, confirm no stale symlink or empty directory remains at the target path.
- When a structural pattern changes significantly (e.g. a symlink becomes a merge-reconcile, a manual command becomes a launchd agent), propose the approach and get approval before implementing.

## Verify

- `nix fmt`, then `nix flake check --impure --no-build` (evaluates every profile) and the warning grep from AGENTS.md "Commands" - no new warnings beyond the documented `options.json` one.
- Build the affected home activation package so every `mkReconcile` script
  is shellchecked rather than only evaluated.
- Diff every config file the change owns: capture path and content before and after the rebuild. Any unintended change is a blocker.
- The user runs `rebuild` themselves; hand them a checklist of what to confirm afterwards.

## Hand Off

- Update `README.md` (keep it short), `docs/architecture.md`, and `docs/gotchas.md` for any user-facing change: new commands, bootstrap steps, package lists, or gotchas.
- Update `AGENTS.md` if the layout tree, invariants, or reconcile table changed.
