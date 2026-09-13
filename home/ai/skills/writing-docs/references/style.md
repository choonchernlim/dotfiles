<!--
Purpose: The writing rules every document produced by writing-docs must satisfy, with the lint code that enforces each.
Type: reference
-->

# Style Rules

Audience: the writer, before drafting and again before handoff.

Every rule names the `lint_docs.py` code that checks it. Rules marked
`[judgement]` have no check and are reviewed by reading.

## Table of Contents

- [Document Shape](#document-shape)
- [Density](#density)
- [Vocabulary](#vocabulary)
- [Meta-Commentary](#meta-commentary)
- [One Fact, One Home](#one-fact-one-home)
- [Links](#links)
- [Line Caps](#line-caps)

## Document Shape

| Rule | Code |
| --- | --- |
| The file opens with a header comment: `Purpose:` line, `Type:` line, nothing else. | `HDR` |
| `Type` is one of `readme-project`, `readme-folder`, `how-to`, `reference`, `explanation`, `index`, `glossary`, `requirements`, `adr`. | `HDR` |
| One H1 follows the header. A README puts its one-line description directly under it. | `TTL` |
| A guide puts one `Audience:` line directly under the H1. | `TTL` |
| A table of contents appears only past 100 lines or 5 H2 sections, and lists every H2. | `TOC` |
| Headings use Title Case. Code identifiers keep their own spelling. | `HCASE` |
| No heading is followed directly by another heading. | `EMPTY` |
| At most 10 H2 sections per file. | `H2N` |
| Every file stays under the line cap for its type (see [Line Caps](#line-caps)). | `CAP` |

Title Case capitalizes every word except articles, conjunctions, and short
prepositions: "Table of Contents", "Adding a Capability", "How the Route
Finds the API". The first and last words are always capitalized.

## Density

| Rule | Code |
| --- | --- |
| A prose run is at most 6 consecutive lines. Break it with a list, table, or diagram. | `RUN` |
| A paragraph holds at most 4 sentences. | `PARA` |
| A sentence holds at most 30 words. Aim for 20. | `SENT` |
| A table cell holds at most 20 words. | `CELL` |
| A bullet holds at most 30 words. Explain with a sub-bullet, not a longer bullet. | `BUL` |
| A list holds at most 7 items. Past that, use a table or split the section. | `LIST` |
| Every code fence names its language. | `FENCE` |

One idea per sentence, one sentence per idea. Prefer a verb to a noun
phrase ("the route validates" over "validation is performed by the route").
Use second person for instructions and active voice everywhere.

## Vocabulary

Banned words are deleted, not replaced. If deleting one loses information,
the sentence needed a fact, not the word. Code: `WORD`.

```text
just simply easy easily trivial straightforward painless obviously of course
delve leverage utilize seamless seamlessly robust comprehensive cutting-edge
powerful innovative streamline empower crucially importantly notably
essentially basically actually
in order to  note that  it should be noted  please note  it's worth noting  in today's
```

A banned word used as a domain term stays: a library named `Seamless`, or
`robust against replay` as a property under test. The rule targets decoration.

Patterns to rewrite `[judgement]`:

- Throat-clearing openers ("Here is the thing", "Let me be clear").
- Reversal framing ("not X, but Y") when plain "Y" says it.
- Significance inflation ("transformative", "critical" as an adjective).
- Synonym cycling. One noun per concept; the glossary term is the noun.
- Vague `-ing` verbs ("fostering", "ensuring", "enabling") in place of a fact.
- Rhetorical questions and closing lines that restate the section.

## Meta-Commentary

A document never talks about its own history, length, or earlier versions.
Readers need the current state. Code: `META`.

```text
this section used to   this document previously   what was one 29-node map
replaces what was      kept for link stability   this corpus now calls
```

## One Fact, One Home

Each category of fact has one owning document, listed in the
[fact-ownership table](guides.md#fact-ownership). Every other document may
spend one sentence on it and must link to the owner. The lint fails when a
12-word run appears in two files, or when a sentence shares half its content
words with a sentence in another file. Code: `DUP`.

## Links

| Rule | Code |
| --- | --- |
| Link text says what the target is. Never "here", "click here", or a bare URL. | `LINK` |
| Links inside the repo are relative paths that resolve from the file's folder. | `LINK` |
| Anchors match a real heading under GitHub slugging. | `LINK` |
| Absolute `github.com/.../blob/...` URLs into this repo are not allowed. | `LINK` |

## Line Caps

| Type | Cap |
| --- | ---: |
| `readme-project` | 150 |
| `readme-folder` | 80 |
| `how-to`, `explanation` | 200 |
| `reference`, `requirements` | 300 |
| `index` | 120 |
| `adr` | 80 |
| `glossary` | none |

Past the cap, split by topic into a linked file. Never trim meaning to fit.
