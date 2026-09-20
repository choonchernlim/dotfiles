#!/usr/bin/env bash
# PostToolUse hook shared by Claude Code (.claude/settings.json) and Codex
# (.codex/hooks.json): formats the .nix files an edit just touched, so neither
# agent spends a turn on `nix fmt` or a failed formatting check.
#
# Reads the hook payload on stdin. Claude names the file in
# tool_input.file_path. Codex edits through apply_patch, whose tool_input
# carries the patch text, so the paths come from its "*** Add File:",
# "*** Update File:" and "*** Move to:" headers, relative to the payload's cwd.
#
# No `set -e`, and every exit is 0: a formatter problem must never fail the
# edit that triggered it. A missing jq or nixfmt is a silent no-op.
set -uo pipefail

command -v jq >/dev/null || exit 0
command -v nixfmt >/dev/null || exit 0

payload="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)"

# Patch headers are searched in every string under tool_input, so this does not
# depend on which key Codex puts the patch text in.
jq -r '
  (.tool_input.file_path? // empty),
  (.tool_input | .. | strings
    | capture("(?:^|\\n)\\*\\*\\* (?:Add File|Update File|Move to): (?<p>[^\\n]+)"; "g").p)
' <<<"$payload" 2>/dev/null | sort -u | while IFS= read -r f; do
  case "$f" in
    *.nix) ;;
    *) continue ;;
  esac
  case "$f" in
    /*) ;;
    *) f="${cwd:-.}/$f" ;;
  esac
  [ -f "$f" ] && nixfmt "$f"
done

exit 0
