<!--
Purpose: Records that architecture decisions are kept as Markdown ADRs in this directory.
Type: adr
-->

# ADR 0001: Record Decisions as ADRs

| Status | Date | Supersedes | Superseded By |
| --- | --- | --- | --- |
| Accepted | 2026-09-13 | - | - |

## Context and Problem Statement

Decisions were made in chat and lost. New developers could not learn why the
system has its shape.

## Considered Options

- Markdown ADRs in the repo.
- A wiki page per decision.

## Decision Outcome

Chosen: Markdown ADRs, because they live next to the code they govern.

1. **One file per decision** under `docs/adrs/`, numbered `NNNN`.
2. **Accepted decisions are immutable.** A change is a new ADR that supersedes clauses.

## Consequences

Good:

- Every decision is reviewable in a pull request.

Bad:

- Writing an ADR takes longer than a chat message.
