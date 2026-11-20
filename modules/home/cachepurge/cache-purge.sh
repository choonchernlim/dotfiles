# cache-purge: reclaim stale tool caches, dev-tree build artifacts and the
# dependency dirs of idle projects.
# Wrapped by ./default.nix in pkgs.writeShellApplication, which supplies the
# shebang, strict mode (set -euo pipefail), and gawk on PATH. Do not add a
# shebang here.
#
# Safety, by design:
#   - tool-native GC (`uv cache prune`, `pip3 cache purge`, ...) runs first;
#     only caches with no such command are ever deleted directly.
#   - direct deletes are scoped to an explicit allowlist of cache directories,
#     or to a fixed set of build-artifact names inside ~/Developer.
#   - staleness is checked by recursively probing for ANY file modified in the
#     last STALE_DAYS, never a directory's own top-level mtime (that signal is
#     wrong: e.g. a JetBrains cache dir with an old mtime but daily writes).
#   - the dev-tree walk never descends into node_modules/.venv/venv/.git and never
#     deletes anything literally named dist/build/coverage - those collide with
#     real installed package dirs and node_modules-internal dirs.
#   - node_modules/.venv/venv themselves are deleted only when their project (the
#     enclosing git repo, else the folder holding them) has had no modified file
#     for STALE_DAYS AND a manifest
#     sits beside them (package.json; pyproject.toml, requirements*.txt, setup.py,
#     Pipfile or uv.lock), so the project itself says how to reinstall them.
#   - the caches a tool GC wipes outright (npm, pip3, yarn, bun, go) are only
#     wiped once nothing in them changed for STALE_DAYS; uv and pnpm prune only
#     what nothing references, so they run every time.
#   - a .terraform/ dir containing an `environment` file (a selected non-default
#     workspace) is skipped; deleting it would silently revert the workspace.
#   - find is always /usr/bin/find: the interactive PATH's `find` is bfs, which
#     rejects -newermt, and GNU find's flags differ from BSD's.

STALE_DAYS=14
DEV_ROOT="$HOME/Developer"

# Dependency dirs deleted with their idle project, as a `find` -name expression.
DEP_DIRS=(node_modules .venv venv)
DEP_FIND=(-name "${DEP_DIRS[0]}")
for d in "${DEP_DIRS[@]:1}"; do DEP_FIND+=(-o -name "$d"); done

# Age-gated cache dirs with no tool-native GC command. Staleness is checked
# per immediate child (each JetBrains IDE version, each playwright build, ...).
AGE_GATED_PARENTS=(
  "$HOME/Library/Caches/JetBrains"
  "$HOME/Library/Caches/ms-playwright"
  "$HOME/Library/Caches/Cypress"
  "$HOME/Library/Caches/copilot"
  "$HOME/Library/Caches/node-gyp"
  "$HOME/Library/Caches/typescript"
  "$HOME/Library/Caches/rancher-desktop-updater"
  "$HOME/.cache/huggingface"
  "$HOME/.cache/whisper"
  "$HOME/.cache/puppeteer"
  "$HOME/.cache/github-copilot"
  "$HOME/.cache/pre-commit"
)

to_delete=()
to_delete_kb=()
stale_kb=0    # stale dirs found (dry) or actually removed (apply/auto)
stale_n=0
gc_freed_kb=0 # measured: cache size before minus after each tool's own GC
gc_freed=""   # "uv 600M, npm 200M" - only tools that freed something
gc_failed=""  # tools whose GC command exited non-zero

# --auto runs inside every rebuild, so it is quiet by design: only deletions
# (STALE) and a short summary print. Dry-run and --apply list everything -
# showing what is excluded, and why, is the dry run's whole job.
QUIET=0

log() { printf '%s\n' "$*"; }
log_verbose() { [ "$QUIET" -eq 1 ] || log "$@"; }

# Always succeeds, even if the path is missing or du fails on it.
dir_size_kb() {
  local d="$1" out=""
  if [ -e "$d" ]; then
    # First line only: a newline in the path would otherwise split the output
    # into extra "sizes" that reach shell arithmetic.
    out=$(du -sk -- "$d" 2>/dev/null | awk 'NR == 1 {print $1}') || out=""
  fi
  case "$out" in
    "" | *[!0-9]*) out=0 ;;
  esac
  printf '%s' "$out"
}

# Scaled so a small figure reads "312M", not "0.0G".
kb_to_human() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.1fG", kb / 1048576
    else if (kb >= 1024) printf "%.0fM", kb / 1024
    else printf "%dK", kb
  }'
}

# True (0) if DIR contains no file modified within STALE_DAYS.
is_stale() {
  local dir="$1"
  [ -e "$dir" ] || return 1
  # -H: a cache dir that is a symlink is probed through the link, not stopped at it.
  if [ -n "$(/usr/bin/find -H "$dir" -mtime "-${STALE_DAYS}" -print -quit 2>/dev/null)" ]; then
    return 1
  fi
  return 0
}

# Queues PATH (SZ kb) for deletion. The STALE line format is parsed by
# scripts/rebuild/format.sh; keep it as is.
record_stale() {
  local path="$1" sz="$2"
  log "  STALE   $(kb_to_human "$sz")  $path"
  to_delete+=("$path")
  to_delete_kb+=("$sz")
  stale_kb=$((stale_kb + sz))
  stale_n=$((stale_n + 1))
}

# Queues PATH when TEST (default: is_stale) holds; otherwise logs it as active,
# so a dry run shows exactly what is excluded and why. Sizing is slow on big
# trees and --auto runs on every rebuild, so only what is queued or listed is sized.
consider() {
  local path="$1" test="${2:-is_stale}"
  if "$test" "$path"; then
    record_stale "$path" "$(dir_size_kb "$path")"
  elif [ "$QUIET" -eq 0 ]; then
    log "  active  $(kb_to_human "$(dir_size_kb "$path")")  $path"
  fi
}

# True (0) if a manifest beside DEP says how to recreate it.
has_manifest() {
  local dep="$1" parent="${1%/*}" f
  if [ "${dep##*/}" = node_modules ]; then
    [ -f "$parent/package.json" ]
    return
  fi
  # "$parent" stays quoted so a glob character in the path is literal; an
  # unmatched requirements*.txt stays literal too and fails the -f test.
  for f in "$parent"/{pyproject.toml,setup.py,Pipfile,uv.lock} "$parent"/requirements*.txt; do
    if [ -f "$f" ]; then return 0; fi
  done
  return 1
}

# DEP's project root: the nearest folder above it, below DEV_ROOT, holding a .git,
# so every package of a monorepo shares the repo's activity; else the folder
# holding DEP.
project_root() {
  local dir="${1%/*}"
  while [ -n "$dir" ] && [ "$dir" != "$DEV_ROOT" ]; do
    if [ -e "$dir/.git" ]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="${dir%/*}"
  done
  printf '%s' "${1%/*}"
}

# True (0) if DEP's project saw no change within STALE_DAYS: no file under the
# project root (.git included, so a pull or commit counts), and nothing at the
# top level of DEP itself (a fresh install). Dependency dirs are not walked.
project_idle() {
  local dep="$1" parent
  parent=$(project_root "$dep")
  [ -z "$(/usr/bin/find "$parent" \( "${DEP_FIND[@]}" \) -prune -o \
    -mtime "-${STALE_DAYS}" -print -quit 2>/dev/null)" ] &&
    [ -z "$(/usr/bin/find "$dep" -maxdepth 1 -mtime "-${STALE_DAYS}" -print -quit 2>/dev/null)" ]
}

scan_age_gated() {
  local parent child
  for parent in "${AGE_GATED_PARENTS[@]}"; do
    [ -d "$parent" ] || continue
    while IFS= read -r -d "" child; do
      consider "$child"
    done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 -print0)
  done
}

is_dep_dir() {
  local d
  for d in "${DEP_DIRS[@]}"; do
    if [ "$d" = "$1" ]; then return 0; fi
  done
  return 1
}

scan_dev_tree() {
  [ -d "$DEV_ROOT" ] || return 0
  local hit name
  while IFS= read -r -d "" hit; do
    name="${hit##*/}"
    if is_dep_dir "$name"; then
      if has_manifest "$hit"; then
        consider "$hit" project_idle
      else
        log_verbose "  skip    (no manifest)  $hit"
      fi
    elif [ "$name" = .terraform ] && [ -e "$hit/environment" ]; then
      log_verbose "  skip    (workspace selected)  $hit"
    else
      consider "$hit"
    fi
  done < <(/usr/bin/find "$DEV_ROOT" \
    -name .git -prune -o \
    -type d \( "${DEP_FIND[@]}" \
      -o -name .next -o -name .wireit -o -name __pycache__ \
      -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \
      -o -name htmlcov -o -name .turbo -o -name .terraform \) \
    -print0 -prune)
}

plural_dirs() { if [ "$1" -eq 1 ]; then printf '1 stale dir'; else printf '%s stale dirs' "$1"; fi; }

# Every `bun pm` subcommand, cache ones included, exits "No package.json was
# found" outside a project (bun 1.4), and activation has no project as its cwd.
# So run it from a scratch dir holding an empty package.json.
bun_cache_rm() {
  local scratch rc=0
  scratch=$(mktemp -d) || return 1
  echo '{}' >"$scratch/package.json"
  (cd "$scratch" && bun pm cache rm) || rc=$?
  rm -rf "$scratch"
  return "$rc"
}

gc_command() {
  case "$1" in
    uv) uv cache prune ;;
    pip3) pip3 cache purge ;;
    npm) npm cache clean --force ;;
    yarn) yarn cache clean ;;
    pnpm) pnpm store prune ;;
    bun) bun_cache_rm ;;
    go) go clean -cache ;;
  esac
}

# Tool-native GC: tried first. uv and pnpm only prune what nothing references,
# so they run every time. The rest empty their whole cache, so they run only
# once the cache has sat idle for STALE_DAYS (a cache in use is a cache worth
# keeping: the next install would re-download all of it). What a tool freed is
# measured (cache size before minus after), never assumed: `uv cache prune`, for
# one, keeps everything still referenced. PATH is extended here: uv/bun/go are
# homebrew, npm/pnpm/yarn are mise shims, and work-atdj has no mise at all.
run_tool_gc() {
  local bin dir gated sz after freed failed
  PATH="/opt/homebrew/bin:$HOME/.local/share/mise/shims:$PATH"
  export PATH
  # A mise shim errors ("not currently active") outside a dir with a mise
  # config, and activation's cwd has none; $HOME resolves to the global config.
  cd "$HOME"
  for bin in uv pip3 npm yarn pnpm bun go; do
    command -v "$bin" >/dev/null 2>&1 || continue
    # gated=1: GC empties the whole cache, so wait until it has sat idle.
    case "$bin" in
      uv) dir="$HOME/.cache/uv" gated=0 ;;
      pip3) dir="$HOME/Library/Caches/pip" gated=1 ;;
      npm) dir="$HOME/.npm" gated=1 ;;
      yarn) dir="$HOME/Library/Caches/Yarn" gated=1 ;;
      pnpm) dir="$HOME/Library/pnpm/store" gated=0 ;;
      bun) dir="$HOME/.bun/install/cache" gated=1 ;;
      go) dir="$HOME/Library/Caches/go-build" gated=1 ;;
      *) dir="" gated=0 ;;
    esac
    if [ "$gated" -eq 1 ] && [ -e "$dir" ] && ! is_stale "$dir"; then
      if [ "$QUIET" -eq 0 ]; then
        log "  GC skip $(kb_to_human "$(dir_size_kb "$dir")")  $bin  (cache used within ${STALE_DAYS}d: $dir)"
      fi
      continue
    fi
    sz=$(dir_size_kb "$dir")
    if [ "$MODE" = "dry" ]; then
      log "  GC      $(kb_to_human "$sz")  $bin  (cache: $dir)"
      continue
    fi
    failed=0
    if ! gc_command "$bin" >/dev/null 2>&1; then
      gc_failed="${gc_failed:+$gc_failed, }$bin"
      failed=1
    fi
    after=$(dir_size_kb "$dir")
    freed=$((sz - after))
    if [ "$freed" -lt 0 ]; then freed=0; fi
    gc_freed_kb=$((gc_freed_kb + freed))
    if [ "$freed" -gt 0 ]; then gc_freed="${gc_freed:+$gc_freed, }$bin $(kb_to_human "$freed")"; fi
    if [ "$failed" -eq 1 ]; then
      log_verbose "  GC      $bin  FAILED  (was $(kb_to_human "$sz"))"
    else
      log_verbose "  GC      $bin  freed $(kb_to_human "$freed")  (was $(kb_to_human "$sz"))"
    fi
  done
}

# Best effort: one undeletable dir must not fail the whole activation, but it
# must not be counted as freed either.
apply_deletes() {
  local i
  for i in "${!to_delete[@]}"; do
    rm -rf -- "${to_delete[$i]}" 2>/dev/null || true
    if [ -e "${to_delete[$i]}" ]; then
      log "cache-purge: could not remove ${to_delete[$i]}"
      stale_kb=$((stale_kb - to_delete_kb[i]))
      stale_n=$((stale_n - 1))
    fi
  done
}

summary() {
  local total=$((gc_freed_kb + stale_kb)) parts="$gc_freed"
  if [ "$MODE" = "dry" ]; then
    if [ "$stale_n" -eq 0 ]; then
      log "cache-purge: dry run - no stale dirs to reclaim (tool GC is not predicted)"
    else
      log "cache-purge: dry run - would reclaim $(kb_to_human "$stale_kb") from $(plural_dirs "$stale_n") (tool GC is not predicted)"
    fi
    return 0
  fi
  if [ "$stale_n" -gt 0 ]; then parts="${parts:+$parts, }$(plural_dirs "$stale_n") $(kb_to_human "$stale_kb")"; fi
  if [ "$total" -gt 0 ]; then
    log "cache-purge: freed $(kb_to_human "$total") ($parts)"
  else
    log "cache-purge: nothing to free"
  fi
  if [ -n "$gc_failed" ]; then log "cache-purge: GC failed: $gc_failed"; fi
}

MODE="dry"
case "${1:-}" in
  --apply) MODE="apply" ;;
  --auto)
    MODE="auto"
    QUIET=1
    ;;
  -h | --help)
    log "usage: cache-purge [--apply|--auto]"
    log "  (no flag)  dry run: report what would be reclaimed, delete nothing"
    log "  --apply    reclaim now"
    log "  --auto     used by the rebuild activation. Quiet: prints only"
    log "             deletions and a one-line summary"
    log "The ${STALE_DAYS}-day staleness gate applies in every mode."
    exit 0
    ;;
  "") ;;
  *)
    echo "cache-purge: unknown argument: $1" >&2
    exit 1
    ;;
esac

log_verbose "cache-purge: mode=$MODE, staleness cutoff=${STALE_DAYS}d"
log_verbose "-- tool-native GC --"
run_tool_gc
log_verbose "-- home caches (age-gated allowlist) --"
scan_age_gated
log_verbose "-- dev tree ($DEV_ROOT) --"
scan_dev_tree

if [ "$MODE" != "dry" ]; then
  apply_deletes
fi

summary
