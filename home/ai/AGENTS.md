# global agent instructions

## Writing style

- Never use the em dash "—"; use a plain dash "-" instead.

## Version control

- Never run `git commit` or `git push` without my explicit approval. First show me the code changes (`git status --short`, `git diff`) and ask me to review them; commit or push only after I approve, and treat each approval as covering that one commit or push only.
- Never add your own agent name as a co-author in commit messages.
- Never manually modify CHANGELOG.md or other files marked as auto-generated.

## Pre-commit review

- After any code change (skip for docs, comments, formatting), before showing the diff for approval:
  1. Simplify the diff (Claude Code: `/simplify`).
  2. Re-run the project's checks (lint, tests, build); fix failures.
  3. Have the `reviewer` subagent review the diff, one pass each in parallel: cohesion (conventions, invariants, docs/tests updated, nothing out of scope); bugs (Claude Code: `/code-review high`; Codex: `/review`); security, only if it touches auth, secrets, input parsing, shell, network, or permissions. No reviewer: do the passes yourself.
  4. Fix confirmed findings and re-run the checks; list the rest with the diff.
- When showing the diff, say which passes ran, on which model, what they changed, and any open findings.

## Engineering priorities

- When making technical decisions, do not weigh development cost heavily. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.
- Follow the patterns of sibling code and reuse existing mechanisms.

## Bug-fixing & testing workflow

- When fixing a bug, first reproduce it end-to-end, as closely as possible to how an end user would experience it. This ensures the fix addresses the real problem. To confirm end-to-end, launch and drive the real app (Claude Code: `/run`).
- When end-to-end testing a product, scrutinize the UI and aim for pixel-perfection. Fix anything that looks off along the way, even if unrelated to the current task.
- Hold the same standard for engineering excellence: fix lint errors, test failures, and test flakiness you encounter, even if unrelated to what you're currently working on.

## Completion summary

- End every reply that finishes a task (files changed, or multi-step work done) with the summary below, so I can reconstruct what happened after running many agents in parallel. Skip it for quick answers, mid-task check-ins, subagent reports, and any request or skill that sets its own output format (e.g. JSON only).
- Use this exact template: same sections, same order, same emojis. Under a section that doesn't apply, write "None" instead of dropping it. This rule takes precedence over any brevity or output-style instruction.
- Write for a reader with no memory of the session: name the repo and branch, give the why behind each change, and reference files as `path:line`.

```markdown
## 🧾 Summary - <repo> @ <branch>

**🎯 Problem:** what I asked for and why, in 1-2 lines
**🚦 Status:** ✅ Done | 🟡 Partial | ❌ Blocked - one line on what is left

### 🛠️ Changes
| Type | What | Why | Where |
|---|---|---|---|
| ✨ Feature / 🐛 Fix / ♻️ Refactor / 🔧 Config / 📝 Docs / 🧪 Test | the change, as a user would notice it | motivation, or root cause for a fix | `path:line` |

### 🧠 Decisions
| Decision | Why | Rejected alternative |
|---|---|---|

### 🧪 Verification
| Check | Result |
|---|---|
| lint / tests / build / e2e / review passes | ✅ / ❌ / ⏭️ skipped, with counts or the reason |

### 📦 State
Uncommitted | committed `<sha>` | pushed - plus anything left running (servers, worktrees, background jobs)

### 🔓 Open topics
- ⚠️ Risks and known issues
- ❓ Questions for me
- 💡 Noticed but out of scope

### 👉 Your next step
- The one thing I should do next (e.g. review the diff and approve the commit)
```
