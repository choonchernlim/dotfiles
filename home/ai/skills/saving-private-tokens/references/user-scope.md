<!--
Purpose: How to read the user-scope section of the audit and act on it without writing outside the audited repository.
Type: how-to
-->

# User Scope

Audience: the agent reporting a `USR-` finding.

The user scope is the config under the home folder that every session loads,
in every repository. The audit reads it on each run and never writes to it.

## Table of Contents

- [Codes This Reports](#codes-this-reports)
- [Read the Section](#read-the-section)
- [Fixable Here or Proposal Only](#fixable-here-or-proposal-only)
- [Write a Proposal](#write-a-proposal)
- [Verify](#verify)

## Codes This Reports

| Code | Meaning | Usual fix |
| --- | --- | --- |
| `USR-INS` | `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md` is over budget. | Move detail out of the global file. Keep only rules that apply everywhere. |
| `USR-SKILL-BUDGET` | Too many skills, or too many description characters, load in every session. | Remove or disable unused skills. Move project-specific skills into that project. |
| `USR-SKILL-DESC` | One user-level skill description is too long. | Shorten the description to its triggers. |

## Read the Section

The section lists findings, then a baseline: what every session costs before
any work starts, measured from the files on disk.

- Each finding ends with `[owner: ...; fixable here]` or `[... proposal only]`.
- The owner is where the file really lives once links are resolved. It is a
  repository path, `this repository`, `no repository`, or
  `Claude Code cloud sync`.
- One instruction file linked for both agents is priced once, because a
  session runs one agent.
- MCP servers are listed by name and priced by estimate. The audit never
  prints their settings, which can hold secrets.

## Fixable Here or Proposal Only

The audited repository is the boundary. Resolve links before judging a path.

| Verdict | Meaning | What to do |
| --- | --- | --- |
| `fixable here` | The file resolves to a tracked file inside the audited repository. | Treat it like any other finding: apply the fix in the repository, then audit again. |
| `proposal only` | The file lives in another repository, in no repository, or in a cloud-synced folder. | Change nothing. Write a proposal. |

A proposal never fails the audit. The exit code counts only what the audited
repository can fix.

Cloud-synced skills sit under a `synced/` folder with a `manifest.json`. They
are downloaded from the user's Claude account on launch, so an edit on disk
is overwritten. The only real fix is in the account's skill settings.

## Write a Proposal

1. Name the finding, its measured cost, and the owner.
2. Show the change as a diff or a command, against the owner's real path.
3. When the owner is another repository, say so: the user runs this skill
   there, where the finding becomes `fixable here`.
4. Stop. The user applies it.

## Verify

1. Audit again. A `fixable here` code has cleared; a proposal is unchanged.
2. In the audited repository, `git status --short` lists only files inside it
   that you meant to change.
3. End the report with the line `Touched outside the repository: none`. If
   that is not true, say exactly what was touched and why.
