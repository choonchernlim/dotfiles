# v006 Spec - Cut Agent Token Usage

## Shared understanding

`/context` reports Bash results at 70.7k tokens (18%) and file reads at 26.4k (7%). The 70.7k is many mid-size outputs, not a few giant ones, because `bashOutputMaxChars` is already 15000 (~4k tokens per call).

Instructions in `AGENTS.md` are advisory and cost tokens in every session, so the fix is short rules plus settings that enforce them:

- Add a terse `## Token discipline` section to the user-level policy `home/ai/AGENTS.md` (symlinked to every agent's canonical path), so it applies in every repo, not just this one.
- Halve the per-call Bash cap in `home/ai/settings/claude.json` from 15000 to 8000.
- No new hooks and no read-deny changes.

## Assumptions

- Confirmed: short rules plus settings enforcement; cap lowered to 8000; no PreToolUse read hook.
- Confirmed: `bashOutputMaxChars` is a live Claude Code settings key here (already set to 15000, so no new key).
- Unconfirmed: 8000 does not truncate useful failure logs often. The quiet-flag rule is meant to prevent that; raise the cap again if it bites.
- Unconfirmed: the Bash savings land mostly on the next session, since `/context` measures the current one.
- The repo `AGENTS.md` Token Discipline section stays as is: it holds repo-specific commands (`nix flake check`), and the new global rules are generic.

## Definition of done

- `home/ai/AGENTS.md` has a `## Token discipline` section of at most 6 bullets, in the file's existing style, with no em dash.
- `home/ai/settings/claude.json` has `"bashOutputMaxChars": 8000` and still parses as JSON.
- `nix flake check --impure --no-build` passes; `scripts/check-warnings.sh` shows no new warning.
- The user's next-session `/context` is the real measure of the savings: they compare the Bash and file-read lines against 70.7k and 26.4k.
