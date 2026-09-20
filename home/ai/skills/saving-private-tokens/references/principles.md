<!--
Purpose: The durable rules behind every playbook, with the measured token costs that justify them.
Type: explanation
-->

# Principles

Audience: the agent deciding which finding to fix first.

Tokens are spent in four places. Each playbook removes one of them with
configuration or a script, so the saving does not depend on model behavior.

## Where Tokens Go

These figures were measured on one mid-sized monorepo. Treat them as orders
of magnitude.

| Cost | Measured | After the fix |
| --- | --- | --- |
| Re-discovering the layout each session | about 22,000 tokens | about 400, from an orientation section |
| Skill descriptions nobody needed | about 1,900 per session | about 200, by scoping skills to folders |
| One accidental lockfile read | 46,000 to 85,000 | blocked by a read deny |
| One skill triggered by mistake | about 6,500 | the skill was deleted |
| Reading a raw log after a failed check | 5,000 to 25,000 per failure | about 300, from inline findings |

## Impact Classes

Every finding carries a class such as `R/XL`. The first part says when the
cost is paid. The second part says how large it is.

| When | Meaning | Size | Tokens |
| --- | --- | --- | --- |
| `S` | every session | `S` | under 1,000 |
| `R` | per file read | `M` | 1,000 to 5,000 |
| `L` | per check loop | `L` | 5,000 to 20,000 |
| `D` | drift that causes rework | `XL` | over 20,000 |

Fix `high` severity first. Within a severity, fix `S` before `R` before `L`,
because a session cost is paid even when nothing goes wrong.

## The Rules

1. **Determinism before intelligence.** If a script can decide it, the model
   should not. A script costs nothing to rerun and gives the same answer.
2. **One entry point.** Every check runs through one command. The command
   list then exists in one place for people, hooks, CI, and both agents.
3. **Quiet by default.** A passing check prints one line. Tool output goes
   to a log file that is read only on failure.
4. **Findings, not logs.** A failure reports `file:line` and a message. The
   agent acts on that without opening the log.
5. **Always-on text is expensive.** Whatever loads every session must earn
   its place. Move detail into files that load on demand.
6. **Block what must never be read.** Lockfiles and generated files get a
   read deny and a Do Not Read entry.
7. **Pay for a failure once.** Turn each pipeline-only failure into a local
   check in the same change.

Three more rules govern how work is done:

- **Script the second time.** Anything done twice by hand becomes a script.
- **Measure first.** Record durations and log sizes before optimizing.
- **Same behavior in both agents.** Shared rules live in `AGENTS.md` and
  shared logic lives under `scripts/`.

## What Not to Optimize

- **Speed is not tokens.** A passing check costs one line whether it ran ten
  tests or five hundred. Test selection saves time, not context.
- **Cached context is cheap, not free.** Trimming a few hundred tokens of
  instructions matters less than removing one 20,000 token log read.
- **Do not trade correctness for brevity.** Never weaken a check, a hook, or
  a permission rule to save tokens.
