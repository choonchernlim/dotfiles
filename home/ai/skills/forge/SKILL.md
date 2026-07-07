---
name: forge
description: Interview the user relentlessly about a plan, design, or coding task until reaching shared understanding, resolving each branch of the decision tree one dependency at a time. For every question, offer a few concrete answer options and mark the recommended one. Use whenever the user wants to forge or stress-test a plan, "get grilled" on their design, or says "forge this" or "grill me" — and also before writing, reviewing, or refactoring any non-trivial code, to surface hidden assumptions, kill unnecessary complexity, keep changes surgical, and pin down verifiable success criteria before a single line is written.
---

# Forge

Take a rough plan and forge it into a sound one by holding it under sustained heat: interview the user relentlessly about every aspect until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. The point is to drag every hidden assumption, ambiguity, and tradeoff into the open *before* any code is written — because the cheapest place to fix a bad decision is in the conversation, not in the diff.

**Tradeoff:** This biases toward caution over speed. For trivial tasks, use judgment and skip ahead.

## How to grill

- **Ask one question at a time.** Wait for the answer before moving to the next branch. Don't dump a questionnaire.
- **Resolve dependencies in order.** Some answers unlock or eliminate later questions. Walk the tree; don't ask about leaves before you've settled the trunk.
- **Explore before asking.** If a question can be answered by reading the codebase, the docs, or the files already in context, go find the answer instead of asking. Only ask the user what genuinely requires their intent or judgment.
- **Always offer options with a recommendation — through the host's interactive picker, not as printed text.** Present each question using the host's native question/selection tool so the user can choose with the arrow keys and Enter. In Claude Code this is the `AskUserQuestion` tool, which renders a real selectable menu. Do *not* hand-print the options as a plain or code-fenced list — that forces the user to type a letter instead of selecting, and a code block can't be navigated at all.

How to map a question onto the picker:

- One question per prompt. Keep it to **at most 4 options** (the picker caps at 4); if you have more candidates, split them across questions.
- Mark the recommendation in that option's label or description (e.g., prefix it with "(Recommended)") and list it first, so it reads as the default.
- The user can still type a free-form answer if none fit, so always leave room to override.

**Example** — *"How should the parser handle malformed input rows?"* becomes a picker with these options:

- **(Recommended) Reject the whole file with a clear error**
- **Skip bad rows, log them, and continue**
- **Coerce to defaults and keep going**

**Fallback only:** if the host has no interactive question tool, print a numbered list and ask the user to type a number. Keep going until there are no unresolved branches.

## What to interrogate

These are the branches worth walking down. Each maps to a common, expensive mistake. The standing engineering rules (minimal diff, surgical edits, YAGNI) live in always-on config — don't restate them here; interrogate whether the *plan* actually honors them.

### 1. Assumptions and interpretations

Don't assume, don't hide confusion, surface tradeoffs.

- What are you silently assuming about inputs, environment, scale, or intent? State each one and confirm it.
- If the request has multiple plausible interpretations, present them as options — don't pick one silently.
- If something is genuinely unclear, name exactly what's confusing rather than papering over it with a guess.

### 2. Scope and simplicity

- Is anything in the plan beyond what was asked? Cut it or justify it.
- Are there abstractions, config knobs, or "flexibility" no one requested? Challenge each.
- Is there error handling for scenarios that can't actually occur?
- Is there a simpler approach? If so, say so and push back. Ask: *"Would a senior engineer call this overcomplicated?"* If yes, simplify before proceeding.

### 3. Surgical changes

- Which exact files and lines will change? Every changed line should trace directly to the request.
- Are you about to touch anything the request didn't ask for — adjacent code, formatting, architecture? Flag it and stop.

### 4. Success criteria

Weak criteria ("make it work") force constant clarification. Strong, verifiable criteria let you loop independently until done.

- How will we *know* this is correct? Turn the goal into something testable:
  - "Add validation" → "Write tests for invalid inputs, then make them pass"
  - "Fix the bug" → "Write a test that reproduces it, then make it pass"
  - "Refactor X" → "Ensure the same tests pass before and after"
- What's the explicit definition of done for each step?

## After the interview

Once every branch is resolved:

1. **Restate the shared understanding** in a few sentences so the user can confirm you landed in the same place.
2. **Lay out a minimal plan** with a verification check per step:
   ```
   1. [Step] → verify: [check]
   2. [Step] → verify: [check]
   3. [Step] → verify: [check]
   ```
3. **Execute and loop** against those checks until each one passes. If a check can't be satisfied as planned, that's a new branch — surface it and grill again rather than guessing.

---

## Credits

This skill is a merge of two open-source skills obtained from GitHub:

- https://github.com/multica-ai/andrej-karpathy-skills/blob/main/skills/karpathy-guidelines/SKILL.md
- https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md
