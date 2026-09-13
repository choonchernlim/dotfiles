<!--
Purpose: The docs/ guide roles, the profile for each Diátaxis type, the index and glossary shapes, and which guide owns which fact.
Type: reference
-->

# Docs Guides

Audience: the writer, when the target is any file under `docs/` other than an ADR.

The README routes; `docs/` holds the depth. Each guide has exactly one type
and one topic. Generate only the roles that have content today; never
scaffold an empty guide so the set looks complete.

## Table of Contents

- [Roles](#roles)
- [Type Profiles](#type-profiles)
- [Index Profile](#index-profile)
- [Glossary Profile](#glossary-profile)
- [Fact Ownership](#fact-ownership)

## Roles

| Role | File | Type |
| --- | --- | --- |
| Index | `docs/README.md` | `index` |
| Glossary | `docs/glossary.md` | `glossary` |
| Architecture | `docs/architecture.md` | `explanation` |
| Runtime flows | `docs/runtime-flows.md` | `explanation` |
| Data model or contracts | `docs/data-model.md` or `docs/contracts.md` | `reference` |
| Operations | `docs/operations.md` | `how-to` |
| Task playbook | `docs/<task>-playbook.md` | `how-to` |
| Requirements | `docs/requirements.md` | `requirements`, see [requirements.md](requirements.md) |
| Decisions | `docs/adrs/` | `adr`, see [adr.md](adr.md) |

A repo may already satisfy a role under another name; extend that file
rather than creating a parallel one.

## Type Profiles

Every guide starts the same way, then follows its type.

```markdown
<!--
Purpose: <one sentence>.
Type: <how-to | reference | explanation>
-->

# Guide Title

Audience: <who reads this> to <answer which question>.

## Table of Contents
```

| Type | Contains | Never Contains |
| --- | --- | --- |
| `how-to` | Goal line, prerequisites, numbered steps with one command each, verification. | Background, rationale, field tables. One sentence of why per step, then a link. |
| `reference` | Tables, field by field. Constraints, defaults, owners. | Procedures, narrative, advice. |
| `explanation` | One diagram block per section, then at most two short paragraphs. | Commands, field tables, step lists other than the diagram's own. |

When a paragraph in a how-to starts explaining, it moves to the explanation
guide and leaves a link. When a reference starts instructing, the steps move
to the how-to guide.

## Index Profile

Cap: 120 lines. Three sections, in this order.

```markdown
## First Week

1. Read [architecture.md](architecture.md). You can name the deployments and who owns each.
2. Read [glossary.md](glossary.md). You can use every domain noun correctly.
3. Read [runtime-flows.md](runtime-flows.md). You can trace one request end to end.
4. Run the checks in the [README](../README.md). You can prove the project is green.

## By Task

| Task | Start Here |
| --- | --- |

## Decisions and History

| Location | Purpose |
| --- | --- |
```

The First Week list has 4 to 6 items, each "read X, then you can Y". The
index does not repeat the Resources table from the root README; it links to
it. Historical folders (`specs/`, `plans/`) get one row each and a sentence
saying the current guides win on conflict.

## Glossary Profile

One alphabetical table, no other sections. No cap.

```markdown
| Term | Meaning | Owning Doc |
| --- | --- | --- |
| Capability card | The JSON a capability serves describing its identity, views, and intents. | [contracts.md](contracts.md#capability-card) |
```

Meaning is one sentence under 20 words. The term is the canonical noun;
every other document uses it and links here instead of redefining it.

## Fact Ownership

One category of fact lives in one document. Every other mention is one
sentence plus a link.

| Fact | Owner |
| --- | --- |
| Extension recipe (how to add a thing) | The task playbook |
| Team and deployment ownership | `architecture.md` |
| Troubleshooting symptoms | `operations.md` |
| Environment variables and ports | `operations.md` |
| Contract and card fields | The contracts or data-model reference |
| Source map of a directory | That directory's folder README |
| Definitions | `glossary.md` |
| Requirement statements | `requirements.md` |
| Why a decision was made | The ADR |
