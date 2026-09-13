<!--
Purpose: The ADR profile, adapted from MADR 4.0, and the rule for what may change in an accepted ADR.
Type: reference
-->

# ADR Profile

Audience: the writer, when recording a decision or normalizing an existing ADR.

One decision per file, named `NNNN-kebab-title.md`, four-digit sequence,
next number is the highest existing plus one. Use the repo's existing ADR
directory; default to `docs/adrs/` only when none exists. Cap: 80 lines. An
ADR never has a table of contents.

## Skeleton

```markdown
<!--
Purpose: Records <what this ADR decides> in one line.
Type: adr
-->

# ADR NNNN: Title

| Status | Date | Supersedes | Superseded By |
| --- | --- | --- | --- |
| Accepted | YYYY-MM-DD | Clauses 2 and 4 of [ADR 0012](0012-older-decision.md) | - |

## Context and Problem Statement

The problem and the forces, in at most two paragraphs. Facts a reader can
check, not an argument.

## Considered Options

- Option A: one line.
- Option B: one line.

## Decision Outcome

Chosen: Option A, because <one sentence>.

1. **First clause.** A self-contained rule naming the concrete things it governs.
2. **Second clause.** Numbered so a later ADR can supersede one clause alone.

## Consequences

Good:

- What becomes easier, with the mechanism.

Bad:

- What becomes harder or is given up. Every decision has these.

## Superseded Clauses

- ADR 0012: clauses 2 and 4 fall; clauses 1 and 3 stand.
```

## Rules

| Rule | Detail |
| --- | --- |
| Status | `Proposed`, `Accepted`, `Rejected`, `Deprecated`, or `Superseded`. When superseded, fill Superseded By. |
| Sections | Context and Problem Statement, Considered Options, Decision Outcome, Consequences. Superseded Clauses only when it supersedes something. |
| Considered Options | Two to five, one line each. The rejected ones say why they lost inside Decision Outcome. |
| Decision Outcome | Numbered clauses. Each cites concrete names in backticks and reads as a rule. |
| Consequences | Both Good and Bad, always. An ADR without Bad is incomplete. |
| Length | Under 80 lines. A longer decision is two decisions. |

## What May Change in an Accepted ADR

The decision is immutable. To change it, write a new ADR whose status table
names what it supersedes, scoped to exact clauses when part of the old
decision stands.

A format-only pass may bring an old ADR to this skeleton: header comment,
heading names and case, the status table, and removal of a table of
contents. The pass never adds, removes, or rewords a sentence inside
Context, Decision, or Consequences. Content under a heading the skeleton
lacks (for example "Rationale") moves under the nearest skeleton heading,
unchanged. The diff must show moved and reformatted lines only.
