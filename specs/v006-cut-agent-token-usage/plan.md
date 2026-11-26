# v006 Plan

- [x] Record the spec and plan pair → verify: both files exist and `refs/grill-me/v6` is reserved
- [x] Add a `## Token discipline` section to `home/ai/AGENTS.md`, after `## Engineering priorities`, with these bullets → verify: re-read the section, at most 6 bullets, no em dash
  - Filter shell output at the source: `grep`, `head`, `tail`, `--quiet`/`--json` flags; send long output to a file and read only the part needed.
  - Read files in slices with `offset` and `limit`; search first, then open the matching range; never re-read a file already in context.
  - Never open lockfiles, generated files, or build artifacts; ask the package manager instead.
  - Ask git for the short form first: `git status --short`, `git diff --stat`, `git log --oneline`.
  - Hand wide searches to a subagent and keep only its conclusion.
  - Run checks quietly and read the summary first, then only the failing check's log.
- [x] Lower `bashOutputMaxChars` from 15000 to 8000 in `home/ai/settings/claude.json` → verify: `python3 -c 'import json;print(json.load(open("home/ai/settings/claude.json"))["bashOutputMaxChars"])'` prints 8000
- [ ] Run `nix fmt`, `nix flake check --impure --no-build`, `scripts/check-warnings.sh` → verify: all green
- [ ] Show the diff for approval (no commit without it) → verify: user approves; the doc-only AGENTS.md change skips the code review passes, and the settings change is one value
- [ ] Hand over a post-change checklist (I never run rebuild; both files are live-symlinked, so no rebuild is needed) → verify: the checklist says to start a new session and compare `/context`

## Files touched

- `home/ai/AGENTS.md`: one new section after `## Engineering priorities`
- `home/ai/settings/claude.json`: the `bashOutputMaxChars` value
- `specs/v006-cut-agent-token-usage/spec.md` and `plan.md`
