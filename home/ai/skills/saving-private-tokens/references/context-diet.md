<!--
Purpose: How to cut what loads into every session: skill scoping, one skill copy, read denies, and MCP placement.
Type: how-to
-->

# Context Diet

Audience: the agent fixing a skill, read-deny, or configuration finding.

Some context is paid for before the first prompt. Other context is paid for
by one careless read. This playbook removes both.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [Keep One Copy of Each Skill](#keep-one-copy-of-each-skill)
- [Scope Skills to Folders](#scope-skills-to-folders)
- [Block Costly Reads](#block-costly-reads)
- [Place MCP Servers](#place-mcp-servers)
- [Verify](#verify)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `SKILL-DUP` | Replace the second copy with a relative link. |
| `SKILL-LINK` | Give both agents the skill, through per-skill relative links. |
| `SKILL-BUDGET` | Move skills to the folder they serve, or delete unused ones. |
| `SKILL-DESC` | Shorten the description and lead with trigger words. |
| `DENY-MISSING` | Add a `Read(...)` deny for the file. |
| `DENY-DEAD` | Remove or correct the pattern. |
| `CFG-PARSE` | Repair the JSON; a broken file disables its hooks and denies. |

## Keep One Copy of Each Skill

Installers often write the same skill into `.claude/skills` and
`.agents/skills`. Two copies drift, and one agent ends up missing a skill.

1. Confirm the trees match before deleting anything:

   ```bash
   diff -rq .agents/skills .claude/skills
   ```

2. Keep the real folder under `.agents/skills/<name>`.
3. Replace each `.claude/skills/<name>` with a relative link:

   ```bash
   ln -s ../../.agents/skills/<name> .claude/skills/<name>
   ```

4. Link each skill, never the whole `skills` folder. Only per-skill links
   are documented for Claude Code.
5. Add a repository test that asserts every `.claude/skills` entry is a link
   to the sibling `.agents/skills` folder of the same name.

Links need macOS or Linux. On Windows keep two copies and add a parity check.

## Scope Skills to Folders

Every skill at the repository root adds its description to every session.
A skill used by one part of the codebase belongs in that part.

1. Move the skill to `<folder>/.agents/skills/<name>` and link it from
   `<folder>/.claude/skills/<name>`.
2. Delete skills the project does not use. Ask before deleting.
3. List each scope and its skills in `AGENTS.md`.

The agents load nested scopes differently. Claude Code loads one when it
first touches a file there. Codex loads one only when launched in that
folder, so tell Codex sessions which `SKILL.md` to read directly.

Moving a skill under a source folder can expose it to that folder's tools.
ESLint 9 lints dot-folders, so add `.agents/**` and `.claude/**` to its
ignores. Make autofixers and formatters skip both folders as well.

## Block Costly Reads

A lockfile read can cost more than the rest of the session.

1. Add deny rules to `.claude/settings.json`:

   ```json
   { "permissions": { "deny": ["Read(**/package-lock.json)", "Read(/data/big.json)"] } }
   ```

2. Use a bare or `**/` pattern for a name at any depth, and a leading `/`
   for one path from the project root.
3. Name the same files under Do Not Read in `AGENTS.md`.
4. Add a test that every deny pattern still matches a file.

A Read deny also blocks Edit and Write on that path. That suits files that
tools regenerate. Do not deny a file the agent is expected to edit by hand.

The audit flags lockfiles and generated files over 2,000 bytes, and data
files over 40,000 bytes. It never flags source code. Files with the same
name share one finding, which names the rule to add.

## Place MCP Servers

Claude Code defers MCP tool schemas, so an idle server costs little. The
cost is in the results: a browser snapshot can be thousands of tokens.

- Remove servers the project does not use.
- Declare a heavy server on an exploration subagent, so its results stay
  out of the main conversation.
- Prefer a script when the same steps will run again.

## Verify

1. Re-run the audit and confirm the code cleared.
2. In Claude Code, run `/context` in a fresh session and compare the skill
   and memory lines with the earlier values.
3. Ask Claude Code to read a denied file and confirm it is refused.
4. Run the project check entry point; moved skills must not break linters.
