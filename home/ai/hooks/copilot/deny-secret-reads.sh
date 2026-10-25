#!/bin/sh
# PreToolUse guard (see docs/gotchas.md): exit 2 denies a tool call whose path
# or shell command names ~/.ssh, ~/.gnupg, or the .env files Claude denies.
# An accident guard, not a security boundary: Copilot has no sandbox, and a
# denylist on shell text cannot catch globs, quoting tricks, or indirection.
# Only paths and commands are checked, never file contents or search
# patterns, so editing or grepping for a mention of ~/.ssh still works. One jq
# call because this runs before every tool call; it fails open on bad input or
# without jq. Case-insensitive because APFS is. $q is a single quote, which the
# single-quoted program cannot contain.
set -eu

[ -x /usr/bin/jq ] || exit 0
if /usr/bin/jq -e --arg q "'" '
  "[\\s/~\"\($q)=;|&<>()`,]" as $b
  | (.toolArgs // .tool_input // {})
  | if type == "string" then (fromjson? // {command: .}) else . end
  | [.path?, .file_path?, .filePath?, .command?, .input?, .glob?, .url?, (.paths? // [])[]?]
  | any(.[] | strings;
      test("(^|\($b))(\\.(ssh|gnupg)|\\.env(\\.local|\\.[^\\s/\"\($q);|&<>()`]+\\.local|\\.production)?)($|\($b))"; "i"))
' >/dev/null 2>&1; then
  echo "Blocked: ~/.ssh, ~/.gnupg, and .env files are off-limits (home/ai/hooks/copilot/deny-secret-reads.sh)." >&2
  exit 2
fi
