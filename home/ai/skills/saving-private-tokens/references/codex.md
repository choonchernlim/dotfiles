<!--
Purpose: Dated facts about Codex that the token-saving playbooks depend on, each with its verification date and source.
Type: reference
-->

# Codex Facts

Audience: the agent applying a playbook, before it relies on tool behavior.

Trust a row until it fails in practice or `audit_tokens.py` reports
`FACT-STALE`. Rows marked `unverified` are assumptions to confirm first.

## Table of Contents

- [Re-verify One Fact](#re-verify-one-fact)
- [Instruction Files](#instruction-files)
- [Skills](#skills)
- [Hooks and Configuration](#hooks-and-configuration)
- [Differences That Change a Playbook](#differences-that-change-a-playbook)

## Re-verify One Fact

Query the one claim in doubt, then correct its row here.

```bash
npx --yes ctx7@latest docs /llmstxt/learn_chatgpt_llms-full_txt "<the claim as a question>"
codex --version
```

The version column reads `docs` when the fact came from documentation and
no local Codex binary was available to confirm it.

## Instruction Files

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CX-01 | Codex loads `AGENTS.md` natively: the global file, then one per folder from the repository root to the launch folder. | 2026-09-19 | docs | learn.chatgpt.com/docs/agent-configuration/agents-md |
| CX-02 | The combined chain is cut at `project_doc_max_bytes`, which defaults to 32,768 bytes. | 2026-09-19 | docs | learn.chatgpt.com/docs/agent-configuration/agents-md |
| CX-03 | `AGENTS.override.md` replaces `AGENTS.md` in the same folder. | 2026-09-19 | docs | learn.chatgpt.com/docs/agent-configuration/agents-md |
| CX-04 | Codex does not strip HTML comments, so marker lines in `AGENTS.md` cost tokens. | 2026-09-19 | unverified | inferred from the AGENTS.md docs |

## Skills

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CX-05 | Codex reads skills from `.agents/skills` in the launch folder, its parent, and the repository root, then `~/.agents/skills`. | 2026-09-19 | docs | learn.chatgpt.com/docs/build-skills |
| CX-06 | A `.agents/skills` folder below the launch folder is never loaded. | 2026-09-19 | docs | learn.chatgpt.com/docs/build-skills |
| CX-07 | Only `name` and `description` load up front. `SKILL.md` loads when the skill is chosen. | 2026-09-19 | docs | learn.chatgpt.com/docs/build-skills |
| CX-08 | Frontmatter limits are 64 characters for `name` and 1,024 for `description`. | 2026-09-19 | unverified | Agent Skills convention |
| CX-09 | Scopes more than two folders below the repository root load when Codex launches there. | 2026-09-19 | unverified | learn.chatgpt.com/docs/build-skills |

## Hooks and Configuration

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| CX-10 | Project hooks live in `.codex/hooks.json` or under `[hooks]` in `.codex/config.toml`. | 2026-09-19 | docs | Codex docs, hooks page |
| CX-11 | Project hooks run only after the user trusts the project. | 2026-09-19 | docs | Codex docs, hooks page |
| CX-12 | A Stop hook continues the turn with `{"decision": "block"}`. | 2026-09-19 | docs | Codex docs, hooks page |
| CX-13 | The `SessionStart` matcher accepts `startup`, `resume`, and `compact`. `clear` is not documented. | 2026-09-19 | unverified | Codex docs, hooks page |
| CX-14 | MCP servers are declared as `[mcp_servers.<name>]` tables in `config.toml`. | 2026-09-19 | docs | Codex docs, MCP page |
| CX-15 | A `deny_read` filesystem permission exists. Its use from project configuration is not confirmed. | 2026-09-19 | unverified | Codex docs, permissions page |

## Differences That Change a Playbook

- **Instruction files.** Codex reads `AGENTS.md`; Claude Code needs the
  `CLAUDE.md` bridge. Keep every shared rule in `AGENTS.md`.
- **Nested skills.** Claude Code loads a nested scope on first file touch.
  Codex loads it only when launched there, so name skill paths in `AGENTS.md`.
- **Read blocking.** Claude Code enforces `Read(...)` denies. For Codex the
  Do Not Read section of `AGENTS.md` is the dependable layer.
- **Hooks.** Both accept the same `SessionStart` and `Stop` shape, so one
  script can serve both. Codex needs the project trusted first.
