#!/bin/bash
# Claude Code status line, adapted from the official docs example:
# https://code.claude.com/docs/en/statusline#display-multiple-lines
# One line: model + effort level, directory, git branch, threshold-colored
# context bar, session cost, and duration. Managed here in dotfiles;
# referenced by settings/claude.json (statusLine.command).
#
# No `set -e`: a status line must always emit a line. Under -e any hiccup
# (jq missing, malformed payload) blanks the whole line instead of degrading
# to the fields that still resolved.
set -uo pipefail

input=$(cat)

# Set CLAUDE_STATUSLINE_DEBUG=/path/to/log to capture raw payloads (e.g. to
# check whether a plan-mode model mismatch is the documented 200k clamp or a
# genuine staleness bug). Zero cost when unset.
if [ -n "${CLAUDE_STATUSLINE_DEBUG:-}" ]; then
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$input" >>"$CLAUDE_STATUSLINE_DEBUG"
fi

# One jq call for every field, not one per field. Emit @tsv and split on
# newlines rather than `IFS=$'\t' read -r a b c`: tab is an IFS whitespace
# char, so adjacent empty fields collapse and every value shifts left the
# moment a field (e.g. .effort.level) is absent.
{
  read -r MODEL
  read -r DIR
  read -r COST
  read -r PCT
  read -r DURATION_MS
  read -r EFFORT
  read -r EXCEEDS
  read -r TRANSCRIPT
} < <(printf '%s' "$input" | jq -r '
  [ .model.display_name // "?",
    .workspace.current_dir // "",
    .cost.total_cost_usd // 0,
    (.context_window.used_percentage // 0 | floor),
    .cost.total_duration_ms // 0,
    .effort.level // "",
    .exceeds_200k_tokens // false,
    .transcript_path // "" ] | @tsv' | tr '\t' '\n')

# Defaults go after the read block, not before: `read` at EOF assigns empty
# *and* returns 1, so a pre-seeded default would be clobbered anyway.
MODEL=${MODEL:-?}
DIR=${DIR:-}
EFFORT=${EFFORT:-}
EXCEEDS=${EXCEEDS:-false}
TRANSCRIPT=${TRANSCRIPT:-}
[[ ${COST:-} =~ ^[0-9]+(\.[0-9]+)?$ ]] || COST=0
[[ ${PCT:-} =~ ^[0-9]+$ ]] || PCT=0
[[ ${DURATION_MS:-} =~ ^[0-9]+$ ]] || DURATION_MS=0
[ "$PCT" -gt 100 ] && PCT=100

# Shorten the verbose 1M suffix Claude Code appends to the display name.
MODEL=${MODEL/ (1M context)/ 1M}

# .effort is absent for models without effort support; the catch-all also
# swallows any level a future release adds that we don't have a label for.
case "$EFFORT" in
  low) EFFORT_LABEL=" - Low" ;;
  medium) EFFORT_LABEL=" - Medium" ;;
  high) EFFORT_LABEL=" - High" ;;
  xhigh) EFFORT_LABEL=" - XHigh" ;;
  max) EFFORT_LABEL=" - Max" ;;
  *) EFFORT_LABEL="" ;;
esac

# Literal escapes via $'...' instead of `echo -e`, so a backslash appearing
# in a directory or branch name below is never reinterpreted.
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
RED=$'\033[31m'; RESET=$'\033[0m'

# opusplan/haiku silently stop upgrading plan mode once the last assistant
# turn's absolute usage passes 200k tokens - a fixed threshold, unrelated to
# the percentage bar below (which is a share of the *effective*, possibly 1M,
# window). That gap is what let plan mode quietly run Sonnet while the bar
# still looked nearly empty. exceeds_200k_tokens is set regardless of
# permission mode, so this marks "the clamp input is set", not "the clamp
# fired" - the strongest signal available from this payload.
CLAMP=""
[ "$EXCEEDS" = "true" ] && CLAMP="${YELLOW} >200k${CYAN}"

# Opt-in cross-check against the transcript's last assistant message. Off by
# default: the transcript only knows what served the *previous* turn, so
# promoting it to primary would show a stale model right after switching
# modes - the very bug this script exists to avoid.
SERVED=""
if [ -n "${CLAUDE_STATUSLINE_VERIFY:-}" ] && [ -r "$TRANSCRIPT" ]; then
  # tail -c can land mid-line, and jq aborts the whole stream on one parse
  # error, hence dropping the (possibly partial) first line with tail -n +2.
  LAST=$(tail -c 262144 "$TRANSCRIPT" 2>/dev/null | tail -n +2 |
    jq -rc 'select(.type=="assistant" and (.isSidechain|not)) | .message.model // empty' \
      2>/dev/null | tail -1)
  case "$LAST" in
    *opus*) LAST=opus ;;
    *sonnet*) LAST=sonnet ;;
    *haiku*) LAST=haiku ;;
    *) LAST="" ;;
  esac
  case "$MODEL" in
    Opus*) NOW=opus ;;
    Sonnet*) NOW=sonnet ;;
    Haiku*) NOW=haiku ;;
    *) NOW="" ;;
  esac
  [ -n "$LAST" ] && [ "$LAST" != "$NOW" ] && SERVED=" ${RED}(served $LAST)${RESET}"
fi

# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
printf -v COST_FMT '$%.2f' "$COST"

BRANCH=""
git --no-optional-locks rev-parse --git-dir > /dev/null 2>&1 \
  && BRANCH=" | 🌿 $(git --no-optional-locks branch --show-current 2>/dev/null)"

printf '%s\n' "${CYAN}[${MODEL}${EFFORT_LABEL}${CLAMP}]${RESET}${SERVED} 📁 ${DIR##*/}${BRANCH} | ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ⏱️ ${MINS}m ${SECS}s"
