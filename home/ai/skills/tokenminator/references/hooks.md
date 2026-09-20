<!--
Purpose: How to give Claude Code and Codex one shared pair of session hooks that run the project checks.
Type: how-to
-->

# Shared Hooks

Audience: the agent fixing a hook finding.

Hooks run the check entry point without the model asking. The agent sees a
short result, and both agents behave the same way.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [The Two Hooks](#the-two-hooks)
- [Wire Both Agents](#wire-both-agents)
- [Rules for the Script](#rules-for-the-script)
- [Verify](#verify)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `HOOK-ONE` | Add the same hooks for the other agent. |
| `HOOK-DIFF` | Make both hook blocks identical. |
| `HOOK-HOME` | Move the hook script under `scripts/`. |

## The Two Hooks

Both hooks call one script. It needs the project's check entry point first,
so apply the check-runner playbook before this one.

| Hook | What it does |
| --- | --- |
| `SessionStart` | Records a hash of every tracked and untracked file. |
| `Stop` | Finds files changed since the start, runs safe fixes, then impacted checks. |

On a failed check the Stop hook blocks once with the failed check ids. If
the next stop fails again, it ends the turn. That prevents a repair loop.

## Wire Both Agents

Use the same block in `.claude/settings.json` and `.codex/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command",
      "command": "\"$(git rev-parse --show-toplevel)/scripts/check\" hook session-start" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "timeout": 1800,
      "command": "\"$(git rev-parse --show-toplevel)/scripts/check\" hook stop" }] }]
  }
}
```

Codex runs project hooks only after the project is trusted.

## Rules for the Script

- **Live under `scripts/`.** Both agents depend on it, so it does not belong
  in one agent's folder.
- **Run through the project wrapper.** The wrapper picks the pinned
  interpreter. A bare `python3` can be too old for the script's syntax.
- **Do nothing in plan mode.** Return an empty result when no edits are
  allowed.
- **Pass the changed files explicitly.** The checks then cover the session's
  work and nothing else.
- **Keep the result short.** Name the failed check ids and the summary path.
  Do not print the log.
- **Test the pairing.** A repository test loads both files and asserts the
  `hooks` objects are equal.

## Verify

```bash
echo '{}' | scripts/check hook session-start
echo '{"permission_mode":"plan"}' | scripts/check hook stop
```

Both print `{}` and exit 0. Then edit a file to break a lint rule, end the
turn, and confirm one block naming the failed check. Re-run the audit last.
