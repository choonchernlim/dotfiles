<!--
Purpose: How to lay out AGENTS.md and CLAUDE.md so both agents read one source, including the managed rules block.
Type: how-to
-->

# Instruction Files

Audience: the agent fixing an instruction-file finding.

Both agents need the same short, accurate instructions at session start.
This playbook gives one source of truth and keeps it from drifting.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [Bridge the Two Agents](#bridge-the-two-agents)
- [Write the Orientation Section](#write-the-orientation-section)
- [Write the Do Not Read Section](#write-the-do-not-read-section)
- [Install the Rules Block](#install-the-rules-block)
- [Keep It Short](#keep-it-short)
- [Verify](#verify)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `AGT-MISSING` | Create a root `AGENTS.md`. |
| `CLD-IMPORT` | Add `CLAUDE.md` beside each `AGENTS.md` with one import line. |
| `CLD-FORK` | Move shared rules out of `CLAUDE.md` into `AGENTS.md`. |
| `ORIENT-MISSING` | Add the orientation section. |
| `DNR-MISSING`, `DNR-UNLISTED` | Add or extend the Do Not Read section. |
| `PATH-DEAD` | Correct or remove the path. |
| `INS-LONG` | Move detail into docs and link to them. |
| `RULES-MISSING`, `RULES-OUTDATED`, `RULES-EDITED` | Run `--fix-rules-block`. |

## Bridge the Two Agents

Codex reads `AGENTS.md`. Claude Code reads `CLAUDE.md` and ignores
`AGENTS.md`. Without a bridge, Claude sessions never see the project rules.

1. Put every shared instruction in `AGENTS.md`.
2. Create `CLAUDE.md` in the same folder containing one line:

   ```text
   @AGENTS.md
   ```

3. Repeat for a nested `AGENTS.md` only when a folder has facts of its own.
4. Keep `CLAUDE.md` for Claude-only notes, and keep those under 15 lines.

## Write the Orientation Section

Name the heading `## Where Things Live`. It replaces the directory listing
and file reading that every new session otherwise repeats.

Include, as one table:

- each deployable unit, its path, and its local port
- the source of truth for contracts or schemas
- the command that starts everything locally
- the infrastructure folder and how environments are separated
- the CI and deploy pipeline files, in the order they trigger
- the check entry point and where its tests live
- a pointer to the docs index, if one routes tasks to guides

Put every path in backticks. The audit reports a path as dead when its
first folder exists in the repository but the rest does not resolve.

## Write the Do Not Read Section

Name the heading `## Do Not Read`. Claude Code can enforce read denies, but
for Codex this section is the dependable layer.

- List lockfiles by name and give the command to use in their place.
- List generated files and point to the source they derive from.
- List large data fixtures.
- Mark superseded plans or specs as history, and name the current docs.

## Install the Rules Block

The block holds working habits that must apply in every session. It is
managed text: never edit it by hand.

```bash
python3 scripts/audit_tokens.py <repo> --fix-rules-block
```

The command writes this text above the orientation heading:

```text
<!-- BEGIN:saving-private-tokens-rules v1 -->
## Token Discipline

- Run checks through the project's single check entry point. Read its summary first, then only the failing check's log.
- Read files in slices with offset and limit. Search first, then open the matching range.
- Never open lockfiles, generated files, or anything under Do Not Read. Ask the package manager instead (`uv tree`, `bun pm ls`, `go list -m all`).
- Prefer quiet and JSON flags over prose output. Send long output to a file and read only the part you need.
- Hand wide searches to a subagent and keep only its conclusion.
- Script anything done twice. Measure durations and log sizes before optimizing a check.
- Test browsers with the scripted Playwright suite. Open one named screenshot only for a visual judgment.
- Use a browser MCP only to explore an unscripted page once, then turn what you learned into a test.
- Managed by the saving-private-tokens skill. Do not edit by hand. Refresh with its audit script and --fix-rules-block.
<!-- END:saving-private-tokens-rules -->
```

If the markers are unpaired or duplicated the command exits 2 and changes
nothing. Repair the markers by hand, then run it again.

## Keep It Short

An instruction file is paid for in every session by both agents.

- Keep each file under 8,000 bytes.
- Keep the root-to-leaf `AGENTS.md` chain under 32,768 bytes, or Codex stops
  reading part way through.
- State a rule once. A nested file adds facts; it does not repeat the root.
- Link to a guide for procedures. Do not paste the procedure.

## Verify

1. Re-run the audit and confirm the code cleared.
2. Start a fresh Claude Code session at the root and confirm the project
   rules are in context.
3. Add a repository test that fails when a backticked path in the
   orientation section does not exist.
