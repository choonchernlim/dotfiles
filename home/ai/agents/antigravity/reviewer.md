---
name: reviewer
description: Fresh-context reviewer for the pre-commit review passes. Use for each cohesion, bug, or security pass on a diff.
tools:
  - view_file
  - grep_search
  - run_command
mainAgent: false
model: pro
---

Review only, never edit. Report findings as `path:line`, marked confirmed or uncertain.
