---
name: saving-private-tokens
description: >
  Cuts AI coding-agent token usage in any repository, the same way for
  Claude Code and Codex. Use when asked to reduce tokens, context, or agent
  cost; when sessions hit context limits or compact often; when an agent
  reads lockfiles, generated files, or giant logs; when setting up or
  reviewing AGENTS.md, CLAUDE.md, skill layout, agent hooks, a quiet check
  runner, read-deny rules, or Playwright e2e for agents; or when preparing a
  repository for agent work. Runs a deterministic audit script, then fixes
  one area at a time from a playbook and re-audits.
---

# Saving Private Tokens

Make a repository cheap for coding agents to work in. Most token waste is
configuration, so a script finds it and a playbook fixes it. This file is the
index: audit, pick one area, apply its playbook, verify, audit again.

Paths below are relative to this skill's folder.

## Workflow

1. **Classify** the repository: apply changes, or audit only.
2. **Audit** with the script and show its output.
3. **Pick one area**, the most expensive finding first.
4. **Apply** that area's playbook and nothing else.
5. **Verify** with the playbook's checks, then audit again.

One area per change. Each change leaves the project's own checks passing.

## Step 1: Classify

Audit only, and change nothing, when any of these hold:

- The repository is not the user's: the remote belongs to someone else, or
  the user has no commits in it. Ask when unsure.
- The finding sits in a vendored folder, a submodule, or generated files.
- The finding's file resolves outside the audited repository. Resolve links
  first: a path under the repository can point elsewhere, and a path under
  the home folder can point back in. The audit marks these `proposal only`.
- The user asked for a review or a report.

Otherwise audit and apply.

## Step 2: Audit

```bash
python3 scripts/audit_tokens.py <repo>
```

Each line reads `CODE severity path:line message (impact, ~before->~after
tok/session basis) -> playbook`. The findings are followed by a per-area
table of tokens per session, before and after the fix, with a TOTAL row. The
basis is `measured` (real file sizes) or `estimated` (the impact class). The
summary line gives counts, detected stacks, and the oldest tool fact. Exit 0
is clean, 1 means findings, 2 means the audit could not run. Add
`--format json` for a machine-readable result, including an `estimates` block.

Show the raw output in the handoff. Do not re-derive findings by reading
the repository; the script already did that without spending tokens.

Every run ends with a read-only `user scope` section: what the config under
the home folder costs in every session, in every repository. Each finding
there names its real owner and is marked `fixable here` or `proposal only`.
`--user` prints that section alone; `--no-user` leaves it out.

The estimates rank areas against each other. They do not predict a bill.
[references/principles.md](references/principles.md) gives the model.

## Step 3: Pick One Area

Order by severity, then by the saving in the audit's per-area table. The
cadence letter in each impact string says when the cost is paid: every
session (`S`), per file read (`R`), per check loop (`L`), drift (`D`). Load
[references/principles.md](references/principles.md) for the measured costs.

| Codes | Area | Playbook |
| --- | --- | --- |
| `AGT-`, `CLD-`, `RULES-`, `ORIENT-`, `DNR-`, `PATH-`, `INS-` | Instruction files | [references/instruction-files.md](references/instruction-files.md) |
| `SKILL-`, `DENY-`, `CFG-` | Context diet | [references/context-diet.md](references/context-diet.md) |
| `RUN-`, `CI-` | Check runner | [references/check-runner.md](references/check-runner.md) |
| `HOOK-` | Shared hooks | [references/hooks.md](references/hooks.md) |
| `PW-`, `MCP-` | Scripted browser tests | [references/e2e.md](references/e2e.md) |
| `TF-` | Infrastructure checks | [references/infrastructure.md](references/infrastructure.md) |
| `USR-` | User scope | [references/user-scope.md](references/user-scope.md) |
| `FACT-` | Tool facts | [references/claude-code.md](references/claude-code.md), [references/codex.md](references/codex.md) |

Fix instruction files first in a new repository. The check runner comes
before hooks, because the hooks call it.

## Step 4: Apply

- Load only the playbook for the chosen area.
- Reuse what the project has. Wrap its existing tools and entry point
  before adding new ones.
- Everything must behave the same in Claude Code and Codex. Shared rules go
  in `AGENTS.md`, shared logic under `scripts/`. A Claude-only setting is an
  extra layer on top, never the only layer.
- Change the rules block only through the script. It composes the text
  for the repository's stacks, so refresh it when the audit asks:

  ```bash
  python3 scripts/audit_tokens.py <repo> --fix-rules-block
  ```

- Trim an over-budget instruction file in one pass. Print the bytes under
  each heading first:

  ```bash
  python3 scripts/audit_tokens.py <repo> --sections
  ```

- A heuristic finding that does not apply is recorded, with a reason, in
  `.agents/saving-private-tokens.json`:

  ```json
  { "ignore": { "CI-DUP:deploy/*.yml": "deploy pipeline, runs no checks" } }
  ```

## Step 5: Verify

1. Run the verify steps at the end of the playbook.
2. Run the project's own check entry point, if it has one.
3. Audit again and confirm the code cleared and no new one appeared.
4. Report the result as a table: each action taken, the area it belongs to,
   and its BEFORE and AFTER tokens per session, with a TOTAL row. Mark each
   number measured or estimated, as the audit does. Take the numbers from
   the two audit runs - the one in step 2 and the one above. Name any
   finding whose estimate the repository contradicts.
5. List files touched, findings deliberately ignored with the reason, and
   anything left undone. Give each `proposal only` finding as a proposal.
6. End with `Touched outside the repository: none`, checked against
   `git status --short`. If it is not true, say what was touched and why.

## Tool Facts

Playbooks depend on how each agent behaves, and that changes. Dated facts
live in the two facts references and in the table that ends the browser
playbook. Trust a row until it fails in practice or the audit reports
`FACT-STALE`. Then re-verify that single row with `ctx7` and update its
date. Never re-read all the documentation up front.

## Hard Limits

- The script's only mutation is the marked block in the root `AGENTS.md`,
  and it refuses a target that resolves outside the repository.
- Never write outside the audited repository, by any tool, shell included.
  A `proposal only` finding is shown to the user and applied by the user.
- Never edit the rules block by hand, and never weaken an existing check,
  hook, or permission rule to save tokens.
- This skill ships no check runner. It states the contract; build the runner
  for the project's stack.
- Never rewrite vendored or third-party skill content. Move it, or delete it
  after asking.
- Never copy this skill into a project. Porting it is the user's decision.
- Never commit unless asked, and add no co-author line.

## Files in This Skill

| File | Purpose |
| --- | --- |
| [references/principles.md](references/principles.md) | The rules and the measured costs behind them |
| [references/instruction-files.md](references/instruction-files.md) | `AGENTS.md`, the `CLAUDE.md` bridge, the rules block |
| [references/context-diet.md](references/context-diet.md) | Skill scoping, one skill copy, read denies, MCP placement |
| [references/check-runner.md](references/check-runner.md) | The check entry point contract |
| [references/hooks.md](references/hooks.md) | One pair of hooks for both agents |
| [references/e2e.md](references/e2e.md) | Scripted Playwright and the browser MCP policy |
| [references/infrastructure.md](references/infrastructure.md) | Offline Terraform tests and tflint |
| [references/user-scope.md](references/user-scope.md) | The user-scope section, ownership, and proposals |
| [references/claude-code.md](references/claude-code.md) | Dated Claude Code facts |
| [references/codex.md](references/codex.md) | Dated Codex facts |
| [scripts/audit_tokens.py](scripts/audit_tokens.py) | The audit; run it, do not read it |
| [scripts/test_audit_tokens.py](scripts/test_audit_tokens.py) | Fixture self-test for the audit |
