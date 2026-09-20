<!--
Purpose: Dated facts about Claude Code that the token-saving playbooks depend on, each with its verification date and source.
Type: reference
-->

# Claude Code Facts

Audience: the agent applying a playbook, before it relies on tool behavior.

Trust a row until it fails in practice or `audit_tokens.py` reports
`FACT-STALE`. Then re-verify that one row, not the whole file.

## Table of Contents

- [Re-verify One Fact](#re-verify-one-fact)
- [Instruction Files](#instruction-files)
- [Skills](#skills)
- [Permissions](#permissions)
- [Hooks and MCP](#hooks-and-mcp)

## Re-verify One Fact

Look up the single claim, then update its date and version in place.

```bash
npx --yes ctx7@latest docs /websites/code_claude "<the claim as a question>"
claude --version
```

A row marked `unverified` is a working assumption. Confirm it before a
playbook step depends on it.

## Instruction Files

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CC-01 | Claude Code loads `CLAUDE.md` and does not load `AGENTS.md` on its own. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/memory |
| CC-02 | A line `@AGENTS.md` inside `CLAUDE.md` imports that file. A symlink also works. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/memory |
| CC-03 | Parent `CLAUDE.md` files load at launch. A nested one loads when Claude first reads a file in that folder. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/memory |
| CC-04 | Block-level HTML comments are removed before the file enters context. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/memory |

## Skills

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CC-05 | Project skills load from `.claude/skills/` in the launch folder and every parent up to the repository root. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/skills |
| CC-06 | A nested `.claude/skills/` loads the first time Claude reads or edits a file in that folder. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/large-codebases |
| CC-07 | A skill entry may be a symlink to a folder elsewhere. A symlinked `skills` folder is not documented. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/skills |
| CC-08 | Skill names always load. Descriptions share about 1% of the context window and are cut short past 1,536 characters. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/settings-reference |
| CC-09 | `disable-model-invocation: true` removes a skill description from context until a user invokes it. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/skills |

## Permissions

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CC-10 | `Read(...)` deny rules use gitignore patterns: `/x` is project root, `//x` is absolute, a bare name matches at any depth. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/permissions |
| CC-11 | A Read deny covers the file tools and Bash commands such as `cat`, `head`, `tail`, `sed`, `grep`, and redirections. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/permissions |
| CC-12 | A Read deny also blocks Edit and Write on that path. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/permissions |
| CC-13 | A Read deny does not cover subprocesses, and `grep -r` over a parent folder still returns the file. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/large-codebases |

## Hooks and MCP

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CC-14 | Project hooks live under `hooks` in `.claude/settings.json`. `Stop` input carries `stop_hook_active` to prevent loops. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/hooks |
| CC-15 | A Stop hook returns `{"decision": "block", "reason": ...}` to request one more turn. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/hooks |
| CC-16 | Tool Search defers MCP tool schemas, so an idle MCP server costs little. Each tool result still enters context. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/mcp |
| CC-17 | An MCP server declared on a subagent stays out of the main conversation. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/sub-agents |
| CC-18 | Project MCP servers are declared in `.mcp.json` at the repository root. | 2026-09-19 | 2.1.277 | code.claude.com/docs/en/mcp |
