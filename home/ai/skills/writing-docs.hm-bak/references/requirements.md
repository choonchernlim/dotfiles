<!--
Purpose: The requirements profile: functional and non-functional requirements grouped by domain, one short user-perspective sentence each.
Type: reference
-->

# Requirements Profile

Audience: the writer, when the target is `docs/requirements.md`.

Requirements state what the product does for its users and what qualities
the system holds. Each one is a single sentence a product owner can read
aloud. Explanation, design, and procedure live elsewhere.

## Shape

Cap: 300 lines. Past that, one file per domain under `docs/requirements/`
with `docs/requirements.md` as the index.

```markdown
<!--
Purpose: The functional and non-functional requirements, grouped by domain, with status and evidence.
Type: requirements
-->

# Requirements

Audience: product owners and maintainers checking what the product must do.

## Table of Contents

## Dashboard

### Functional

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| DASH-001 | A clinician MUST be able to reopen a saved dashboard by URL without replaying chat. | Implemented | [dashboard.spec.ts](../ui/e2e/dashboard.spec.ts) |

### Non-Functional

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| DASH-N01 | The system MUST persist every dashboard change atomically with a revision check. | Implemented | [test_store.py](../platform/tests/test_store.py) |
```

## Rules

| Rule | Detail |
| --- | --- |
| Domains | One H2 per domain, named with a glossary term. Each has a Functional and a Non-Functional H3. |
| Sentence | One sentence, at most 25 words. Functional ones start with the user: "A clinician MUST be able to". |
| Keywords | RFC 2119 words in capitals: MUST, MUST NOT, SHALL, SHOULD, MAY. One keyword per requirement. |
| ID | `DOMAIN-NNN` for functional, `DOMAIN-NNN` with an `N` prefix on the number for non-functional. Never reused. |
| Status | `Implemented`, `Gap`, or `Future`. |
| Evidence | One link to a test, spec, or source file. Not a list, not prose. |
| Prose | At most one sentence between a heading and its table. |

A requirement that needs two sentences is two requirements. A requirement
that names a file, class, or function is describing a design; move that
detail to the evidence link and restate the behavior the user sees.

## Non-Functional Domains

Non-functional rows cover qualities, not features: performance, security,
reliability, accessibility, and operability. They still read from the
outside: "The system MUST respond to a tile request within 10 seconds or
show an error for that tile only."
