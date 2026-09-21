#!/usr/bin/env bash
# Turns the raw `rebuild` stream (stdin) into a grouped, emoji-annotated summary
# (stdout). rebuild.sh owns the raw stream: it tees it to a log first, so this
# script only presents and can never lose information.
#
# Contract - keep it when adding rules:
#   - one rule per known line shape, in the `case` below. A line matching no
#     rule is printed dimmed under the current section, never dropped: if
#     upstream rewords a message the output gets noisier, not quieter.
#   - a known warning is collapsed to a count; every other `warning:` prints in
#     full with a nudge to investigate (docs/gotchas.md: a new warning is a
#     regression).
#   - bash 3.2 compatible (macOS /bin/bash): no associative arrays, no
#     `${var,,}`, no `mapfile`.
#
# Env:
#   REBUILD_FORMAT_TIMES=0  omit clock times and durations, and the live status
#                           line - deterministic output for the golden test
#   NO_COLOR                disable ANSI colour (also off when stdout is no tty)
set -euo pipefail

TIMES="${REBUILD_FORMAT_TIMES:-1}"
DIM="" RED="" YEL="" RST=""
LIVE=0
if [ -t 1 ]; then
  if [ -z "${NO_COLOR:-}" ]; then
    DIM=$'\e[2m' RED=$'\e[31m' YEL=$'\e[33m' RST=$'\e[0m'
  fi
  # The in-place status line replaces Nix's progress bar, which is lost once
  # the stream is piped.
  if [ "$TIMES" != 0 ]; then LIVE=1; fi
fi

cur=""              # current section id: sync|build|system|homebrew|home
sec_start=0
profile=""
had_error=0
# sync
sync_target="" sync_range="" autostash_noted="" hmbak_seen=0 hmbak=0
# build
known_warns="" n_known=0 n_built=0 n_fetched=0 in_list=0
# system
n_steps=0
# homebrew
brew_up="" brew_inst="" brew_rm="" brew_deps="" in_new=0
# home
n_act=0 links_seen=0 agy_ver="" mcp_gone="" mcp_done=0

TICK_STATE="" TICK_PID=""
re_newpkg='^[a-z0-9@+._/-]+: .+' # a "name: description" line of brew's new-casks report

now() { if [ "$TIMES" = 0 ]; then echo 0; else date +%s; fi; }

fmt_dur() {
  local s="$1"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}

# Every line goes through emit: on a tty the leading \r\e[2K wipes the status
# line in the same write, so a redraw racing this print can never leave residue.
emit() {
  if [ "$LIVE" -eq 1 ]; then printf '\r\033[2K%s\n' "$*"; else printf '%s\n' "$*"; fi
}

row() {
  local r
  printf -v r '   %s %-9s %s' "$1" "$2" "$3"
  emit "$r"
}

# A summary line with no label column.
note() { emit "   $1 $2"; }

# Marks a line as deliberately consumed (its information is folded into a
# summary row, or it is pure noise). A no-op, but it keeps an intentionally
# silent rule distinguishable from a forgotten one.
drop() { :; }
passthru() { emit "   ${DIM}· ${line}${RST}"; }

tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

known_warn() {
  n_known=$((n_known + 1))
  case ",$known_warns," in
    *",$1,"*) ;;
    *) known_warns="${known_warns:+$known_warns, }$1" ;;
  esac
  drop
}

set_tick() {
  if [ "$LIVE" -eq 1 ]; then printf '%s|%s\n' "$1" "$(now)" >"$TICK_STATE"; fi
}

start_ticker() {
  if [ "$LIVE" -ne 1 ]; then return 0; fi
  TICK_STATE="$(mktemp)"
  (
    while :; do
      sleep 1
      label="" start=""
      IFS='|' read -r label start <"$TICK_STATE" || true
      # Empty while a section may prompt (sync: sudo -v reads the tty) - drawing
      # then would erase the password prompt.
      if [ -n "$label" ] && [ -n "$start" ]; then
        printf '\r\033[2K   ⏳ %s  %s' "$label" "$(fmt_dur $(($(date +%s) - start)))"
      fi
    done
  ) &
  TICK_PID=$!
}

stop_ticker() {
  if [ -n "$TICK_PID" ]; then
    kill "$TICK_PID" 2>/dev/null || true
    wait "$TICK_PID" 2>/dev/null || true
    TICK_PID=""
    printf '\r\033[2K'
  fi
  if [ -n "$TICK_STATE" ]; then rm -f "$TICK_STATE"; TICK_STATE=""; fi
}

plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi; }

# full: the section ended normally (next sentinel or clean EOF).
# cut:  the stream ended mid-section after an error - print no success lines.
flush_section() {
  local mode="$1" d=""
  case "$cur" in
    sync)
      if [ "$mode" = full ] && [ "$hmbak_seen" -eq 1 ] && [ "$hmbak" -eq 0 ]; then
        note "✓" "no stale *.hm-bak backups"
      fi
      ;;
    build)
      if [ "$mode" = full ]; then
        if [ "$TIMES" != 0 ]; then d="  ($(fmt_dur $(($(now) - sec_start))))"; fi
        note "✓" "system configuration${d}"
      fi
      if [ "$n_built" -gt 0 ] || [ "$n_fetched" -gt 0 ]; then
        note "📦" "$(plural "$n_built" derivation) built, $(plural "$n_fetched" path) fetched"
      fi
      if [ "$n_known" -gt 0 ]; then
        note "⚠" "$(plural "$n_known" "known warning"): ${known_warns}"
      fi
      ;;
    system)
      if [ "$mode" = full ]; then note "✓" "$(plural "$n_steps" step)"; fi
      ;;
    homebrew)
      if [ -n "$brew_up" ]; then row "⬆" upgraded "$brew_up"; fi
      if [ -n "$brew_inst" ]; then row "⬇" installed "$brew_inst"; fi
      if [ -n "$brew_rm" ]; then row "🗑" removed "$brew_rm"; fi
      if [ "$mode" = full ] && [ -n "$brew_deps" ]; then note "✓" "$brew_deps deps in sync"; fi
      ;;
    home)
      if [ -n "$mcp_gone" ] && [ "$mcp_done" -eq 0 ]; then
        row "⚠" claude "MCP server $mcp_gone removed but not re-added"
      fi
      if [ "$mode" = full ]; then note "✓" "$n_act activation steps"; fi
      ;;
  esac
}

section() { # section ID ICON TITLE
  flush_section full
  cur="$1"
  sec_start="$(now)"
  # rebuild.sh reads this back to name the phase that failed.
  if [ -n "${REBUILD_PHASE_FILE:-}" ]; then printf '%s\n' "$3" >"$REBUILD_PHASE_FILE"; fi
  emit ""
  emit "$2 $3"
  case "$1" in
    sync) set_tick "" ;;
    *) set_tick "$3" ;;
  esac
}

finish() {
  if [ "$had_error" -eq 1 ]; then flush_section cut; else flush_section full; fi
  stop_ticker
}
trap stop_ticker EXIT

start_ticker

while IFS= read -r line || [ -n "$line" ]; do
  # Nix progress redraws with \r; keep what a terminal would finally show.
  line="${line##*$'\r'}"
  case "$line" in
    *$'\e'*) line="$(printf '%s' "$line" | sed $'s/\e\\[[0-9;]*[A-Za-z]//g')" ;;
  esac
  if [ -z "${line//[[:space:]]/}" ]; then continue; fi

  # Brew's "New Casks/Formulae" report: a header, then `name: description` lines.
  if [ "$in_new" -eq 1 ]; then
    case "$line" in
      warning:* | error:*) in_new=0 ;;
      *)
        if [[ "$line" =~ $re_newpkg ]]; then
          drop
          continue
        fi
        in_new=0
        ;;
    esac
  fi
  # Nix's "these N derivations will be built:" is followed by indented store paths.
  if [ "$in_list" -eq 1 ]; then
    case "$line" in
      "  /nix/store/"*)
        drop
        continue
        ;;
      *) in_list=0 ;;
    esac
  fi

  case "$line" in
    # ---- rebuild.sh / sync-skills.sh -------------------------------------
    ">> profile: "*)
      profile="${line#>> profile: }"
      if [ "$TIMES" != 0 ]; then
        emit "🔧 rebuild  ${profile}  ·  $(date +%H:%M:%S)"
      else
        emit "🔧 rebuild  ${profile}"
      fi
      section sync "📥" sync
      drop
      ;;
    ">> syncing repo:"*)
      sync_target=dotfiles
      drop
      ;;
    ">> syncing skills repo:"*)
      sync_target=skills
      drop
      ;;
    ">> on branch "*)
      b="${line#*\'}"
      row "ℹ" dotfiles "on branch '${b%%\'*}' - pull skipped"
      drop
      ;;
    ">> skills repo on branch "*)
      b="${line#*\'}"
      row "ℹ" skills "on branch '${b%%\'*}' - pull skipped"
      drop
      ;;
    ">> cloning skills repo:"*)
      sync_target=skills
      row "⬇" skills "cloning ${line#>> cloning skills repo: }"
      drop
      ;;
    ">> clearing stale"*)
      hmbak_seen=1
      drop
      ;;
    /*.hm-bak)
      hmbak=$((hmbak + 1))
      row "🧽" backup "removed $(tilde "$line")"
      drop
      ;;
    "Already up to date." | "Current branch "*" is up to date."*)
      row "✓" "${sync_target:-repo}" "up to date"
      drop
      ;;
    "Created autostash: "* | "Applied autostash."*)
      case ",$autostash_noted," in
        *",${sync_target},"*) ;;
        *)
          autostash_noted="${autostash_noted:+$autostash_noted,}${sync_target}"
          row "↺" "${sync_target:-repo}" "local edits autostashed"
          ;;
      esac
      drop
      ;;
    "Updating "*..*)
      sync_range="${line#Updating }"
      drop
      ;;
    # git's fast-forward diffstat; only meaningful inside the sync section.
    "Fast-forward" | " "*" | "* | " create mode "* | " delete mode "* | " rename "* | " mode change "* | " "*" file"*" changed"*)
      if [ "$cur" = sync ]; then drop; else passthru; fi
      ;;
    "Successfully rebased and updated "*)
      row "⬆" "${sync_target:-repo}" "updated ${sync_range}"
      drop
      ;;

    # ---- nix build -------------------------------------------------------
    "building the system configuration..."*)
      section build "🔨" build
      drop
      ;;
    "warning: Using 'builtins.derivation' to create a derivation named 'options.json'"*)
      known_warn "options.json (upstream)"
      ;;
    "warning: Git tree '"*"' has uncommitted changes" | "warning: Git tree '"*"' is dirty")
      known_warn "dirty git tree"
      ;;
    "warning:"*)
      emit "   ${YEL}❗ ${line}${RST}"
      emit "      ${DIM}↑ unknown warning - investigate before committing${RST}"
      ;;
    "error:"*)
      had_error=1
      emit "   ${RED}❌ ${line}${RST}"
      ;;
    "building '/nix/store/"*)
      n_built=$((n_built + 1))
      drop
      ;;
    "copying path '"*)
      n_fetched=$((n_fetched + 1))
      drop
      ;;
    "these "*" will be built:" | "this derivation will be built:" | "these "*" will be fetched"* | "this path will be fetched"*)
      in_list=1
      drop
      ;;

    # ---- nix-darwin system steps ----------------------------------------
    "setting up "* | "applying patches..."* | "configuring "* | "setting nvram variables..."*)
      case "$cur" in
        homebrew | home) passthru ;;
        *)
          if [ "$cur" != system ]; then section system "🍎" system; fi
          n_steps=$((n_steps + 1))
          drop
          ;;
      esac
      ;;

    # ---- homebrew --------------------------------------------------------
    "Homebrew bundle..."*)
      section homebrew "🍺" homebrew
      drop
      ;;
    "==> Auto-updating Homebrew..."* | "==> Auto-updated Homebrew!"* | "==> Downloading https://formulae.brew.sh/"* | "Updated "*" tap"*)
      drop
      ;;
    "==> Homebrew's analytics have entirely moved"* | "We gather less data than before"* | \
      "Please reconsider re-enabling analytics"* | "  brew analytics on"*)
      drop
      ;;
    "Adjust how often this is run"* | "==> Homebrew collects anonymous analytics."* | "Read the analytics documentation"* | \
      "  https://docs.brew.sh/Analytics"* | "No analytics have been recorded"* | "==> Homebrew is run entirely by unpaid"* | \
      "  https://github.com/Homebrew/brew#-donations"*)
      drop
      ;;
    "==> New Casks"* | "==> New Formulae"*)
      in_new=1
      drop
      ;;
    "You have "*" outdated "*)
      t="${line#You have }"
      t="${t% installed.}"
      note "ℹ" "${t// and /, }"
      drop
      ;;
    "Fetching "*)
      row "⬇" fetching "${line#Fetching }"
      drop
      ;;
    "Using "*)
      drop
      ;;
    "Upgrading "*)
      brew_up="${brew_up:+$brew_up, }${line#Upgrading }"
      drop
      ;;
    "Installing "*)
      brew_inst="${brew_inst:+$brew_inst, }${line#Installing }"
      drop
      ;;
    "Removing: "*"/Cellar/"*)
      rest="${line#*/Cellar/}"
      size=""
      case "$line" in
        *", "*)
          size="${line##*, }"
          size=" (${size%)})"
          ;;
      esac
      brew_rm="${brew_rm:+$brew_rm, }${rest%%/*}${size}"
      drop
      ;;
    "==> This operation has freed approximately "*)
      drop
      ;;
    "\`brew bundle\` complete! "*)
      n="${line#*complete! }"
      brew_deps="${n%% *}"
      drop
      ;;
    "\`brew bundle\` failed!"*)
      had_error=1
      emit "   ${RED}❌ ${line}${RST}"
      ;;

    # ---- home-manager ----------------------------------------------------
    "Activating home-manager configuration for "*)
      section home "🏠" home
      drop
      ;;
    "Starting Home Manager activation"* | "File modified: "*)
      drop
      ;;
    "Activating "*)
      n_act=$((n_act + 1))
      drop
      ;;
    "Cleaning up orphan links from "* | "Creating home file links in "*)
      if [ "$links_seen" -eq 0 ]; then row "🔗" links refreshed; fi
      links_seen=1
      drop
      ;;
    "⟳ Checking for updates... (current version "*")")
      agy_ver="${line#*current version }"
      agy_ver="${agy_ver%)}"
      drop
      ;;
    "✓ You are already on the latest version."*)
      row "🤖" agy "${agy_ver:-current} (latest)"
      drop
      ;;
    "Removed MCP server "*" from user config")
      mcp_gone="${line#Removed MCP server }"
      mcp_gone="${mcp_gone%% *}"
      drop
      ;;
    "Added stdio MCP server "*)
      m="${line#*MCP server }"
      m="${m%% *}"
      if [ "$m" = "$mcp_gone" ]; then
        row "🔌" claude "$m MCP re-registered"
      else
        row "🔌" claude "$m MCP registered"
      fi
      mcp_done=1
      drop
      ;;
    "  STALE   "*)
      rest="${line#  STALE   }"
      row "🗑" stale "${rest%% *}  $(tilde "${rest#*  }")"
      drop
      ;;
    "cache-purge: GC failed: "*)
      row "⚠" cache "GC failed: ${line#cache-purge: GC failed: }"
      drop
      ;;
    "cache-purge: could not remove "*)
      row "⚠" cache "could not remove $(tilde "${line#cache-purge: could not remove }")"
      drop
      ;;
    "cache-purge: freed "* | "cache-purge: nothing to free"* | "cache-purge: skipped "*)
      row "🧹" cache "${line#cache-purge: }"
      drop
      ;;

    *) passthru ;;
  esac
done

finish
