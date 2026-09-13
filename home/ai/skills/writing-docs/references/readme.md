<!--
Purpose: The PROJECT and FOLDER README profiles, the minimum shape each README takes and the caps it stays under.
Type: reference
-->

# README Profiles

Audience: the writer, when the target is a README.md at any level.

Pick the profile from the folder, not from the existing file. A repo,
package, or runnable-project root takes PROJECT. A directory inside the
source tree takes FOLDER. A profile is the minimum shape: a section with no
content is omitted, never left empty.

## PROJECT Profile

Cap: 150 lines. The first runnable command appears within two screens.

```markdown
<!--
Purpose: Entry point for <project>: what it is, how to run it, where the guides live.
Type: readme-project
-->

# Project Name

One sentence, under 120 characters, saying what this project is.

## Table of Contents

(Only when the file exceeds 100 lines.)

## Introduction

Two or three plain sentences: the problem, who has it, what this does about
it. No identifiers or paths yet.

(one diagram block, see the mermaid reference)

| Inventory | Current Set |
| --- | --- |

## Getting Started

### Prerequisites

Tools and versions, one bullet each, with install links.

### Installation

Numbered steps from clone to configured, one runnable command each.

### Usage

The run command, what to expect, and a "Run the Checks" subsection.

## Resources

| Resource | What It Answers |
| --- | --- |
| [docs/README.md](docs/README.md) | Where to start and which guide answers which task |
```

Fill guidance:

- The Introduction routes; depth lives in `docs/`. Every fact here is one
  sentence plus a link to its owner.
- The Resources table lists the docs index, every guide, and the ADR
  directory, one row each.
- Contributing, license, and security link to their own files.
- No "Adding a Capability" or similar recipe here. The how-to guide owns it;
  the Introduction links it in one sentence.

## FOLDER Profile

Cap: 80 lines, at most one diagram. A folder README orients a developer who
is already inside the project, so it has no prerequisites or installation.

```markdown
<!--
Purpose: What <folder> owns, its entrypoints, and how to extend it.
Type: readme-folder
-->

# Folder Name

One sentence saying what this folder owns and what it does not.

## Entrypoints

- `file.ts`: what other code imports from it, in one line.

## File Ownership

| File | Owns | Direct Callers |
| --- | --- | --- |

## How to Extend

Where a new implementation is declared, and what must not be edited.

## Verification

The commands that prove a change here is safe.
```

Fill guidance:

- Entrypoints: at most 7 bullets. Past that, the folder is two folders.
- File Ownership lists hand-written runtime files only. Tests, styles, and
  generated artifacts are omitted.
- Cross-cutting facts (team ownership, extension rule, contracts) are one
  sentence plus a link to the owning `docs/` guide, never restated.
- The optional diagram shows this folder's internal dependencies only.
