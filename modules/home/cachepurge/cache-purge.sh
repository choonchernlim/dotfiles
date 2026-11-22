# cache-purge: reclaim stale tool and app caches, superseded IDE settings and
# Xcode device symbols, dev-tree build artifacts and the dependency dirs of
# idle projects.
# Wrapped by ./default.nix in pkgs.writeShellApplication, which supplies the
# shebang, strict mode (set -euo pipefail), and gawk on PATH. Do not add a
# shebang here.
#
# Safety, by design:
#   - tool-native GC (`uv cache prune`, `pip3 cache purge`, ...) runs first;
#     only caches with no such command are ever deleted directly.
#   - direct deletes are scoped to an explicit allowlist of cache directories,
#     superseded version dirs under two fixed parents (JetBrains settings, Xcode
#     DeviceSupport), or a fixed set of build-artifact names inside ~/Developer.
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
#   - the caches a tool GC wipes outright (npm, pip3, yarn, bun, go build, go modules) are only
#     wiped once nothing in them changed for STALE_DAYS; uv and pnpm prune only
#     what nothing references, so they run every time.
#   - simulators are never deleted: Xcode calls one "unavailable" also when the
#     selected Xcode merely lacks its runtime (a beta beside stable), and its
#     app data would go with it.
#   - the Adobe Camera Raw caches are deleted only whole (their chunks share an
#     index), once nothing in them changed for STALE_DAYS, and never while an
#     Adobe app that reads them is running.
#   - a JetBrains settings dir (Application Support) is user config, not a
#     cache: it goes only when a newer version of its product sits beside it, no
#     installed IDE app claims it (product-info.json's dataDirectoryName), it
#     holds no scratch files or database consoles, and it is stale. An IDE still
#     installed keeps its settings however long it idles. A dir kept only for its
#     scratches or consoles still loses its plugins/ (reinstallable, and the
#     bulk of it) once that is stale.
#   - Xcode DeviceSupport dirs are written once, at a device's first connect on
#     an OS build, and only read after, so their mtime cannot tell in-use from
#     idle. The newest per device model is always kept; older builds are
#     age-gated.
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
  "$HOME/Library/Logs/JetBrains"
  "$HOME/Library/Developer/Xcode/DerivedData"
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

# Deleted only whole and only while no Adobe app runs; see the header.
CAMERA_RAW_CACHES=(
  "$HOME/Library/Caches/Adobe Camera Raw 2"
  "$HOME/Library/Caches/Adobe Camera Raw BigTableGroupCache"
)
# pgrep -f pattern: the executable path of every Adobe app that reads them.
ADOBE_APPS='/Adobe (Lightroom|Photoshop|Bridge|After Effects|DNG Converter)[^/]*\.app/Contents/MacOS/'

# Keep-newest parents (see the header): per-version IDE settings
# (<Product><YYYY.N>) and per-build device symbols (<Model> <OS> (<build>)).
JETBRAINS_SETTINGS="$HOME/Library/Application Support/JetBrains"
DEVICE_SUPPORT_PARENTS=(
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/visionOS DeviceSupport"
)

# Where IDE apps are installed: anywhere Spotlight indexes (bundle id
# com.jetbrains.*), plus these globs for when it is off: /Applications,
# ~/Applications (Toolbox 2) and Toolbox 1's own apps dir. Each app's
# product-info.json names its settings dir.
IDE_PRODUCT_INFO_GLOBS=(
  "/Applications/*.app/Contents/Resources/product-info.json"
  "$HOME/Applications/*.app/Contents/Resources/product-info.json"
  "$JETBRAINS_SETTINGS/Toolbox/apps/*/ch-*/*/*.app/Contents/Resources/product-info.json"
)
declare -A INSTALLED_IDE_DIRS=()

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

# True (0) if DIR contains no file modified within STALE_DAYS. A find error (an
# unreadable subdir could hide a fresh file) counts as not stale.
is_stale() {
  local dir="$1" hit
  [ -e "$dir" ] || return 1
  # -H: a cache dir that is a symlink is probed through the link, not stopped at it.
  hit=$(/usr/bin/find -H "$dir" -mtime "-${STALE_DAYS}" -print -quit 2>/dev/null) || return 1
  [ -z "$hit" ]
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
  local parent child dir adobe=0 rc=0
  for parent in "${AGE_GATED_PARENTS[@]}"; do
    [ -d "$parent" ] || continue
    while IFS= read -r -d "" child; do
      consider "$child"
    done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 -print0)
  done
  # Matched on the app executable's path, so an unrelated command line that
  # mentions an app name does not count. pgrep exits 1 for no match; anything
  # else (an error) counts as running.
  /usr/bin/pgrep -f "$ADOBE_APPS" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 1 ]; then adobe=1; fi
  for dir in "${CAMERA_RAW_CACHES[@]}"; do
    [ -d "$dir" ] || continue
    if [ "$adobe" -eq 1 ]; then
      log_verbose "  skip    (Adobe app running)  $dir"
    else
      consider "$dir"
    fi
  done
}

# Rank functions for scan_keep_newest: set RANK_GROUP and RANK (an integer,
# higher is newer) for dir $1, or return 1 to leave the dir out entirely.
# 10#: a zero-padded version must not be read as octal.
jetbrains_rank() {
  [[ "${1##*/}" =~ ^([A-Za-z]+)([0-9]{4})\.([0-9]{1,3})$ ]] || return 1
  RANK_GROUP=${BASH_REMATCH[1]}
  RANK=$((10#${BASH_REMATCH[2]} * 1000 + 10#${BASH_REMATCH[3]}))
}

# "iPhone18,2 27.2.1 (24B156)": the model, then the OS version. Legacy names
# ("16.4 (20E247)") carry no model, so they share one group. Ranked by the
# version in the name, not a timestamp: copies can carry the device's times.
device_support_rank() {
  local re='^(([^ ]+,[^ ]+) )?([0-9]{1,3})\.([0-9]{1,3})(\.([0-9]{1,3}))? '
  [[ "${1##*/}" =~ $re ]] || return 1
  RANK_GROUP=${BASH_REMATCH[2]:-legacy}
  RANK=$((10#${BASH_REMATCH[3]} * 1000000 + 10#${BASH_REMATCH[4]} * 1000 + 10#${BASH_REMATCH[6]:-0}))
}

# Guard for scan_keep_newest: succeeds (and sets KEEP_REASON) when settings
# dir $1 belongs to an installed IDE, or holds files the user wrote (scratch
# files, database consoles) that no newer version imported. In the second case
# it also sets KEEP_PARTIAL: plugins/ is reinstallable binaries and the bulk of
# a settings dir, so it is still reclaimed on its own once stale.
jetbrains_keep() {
  local sub
  if [ -n "${INSTALLED_IDE_DIRS[${1##*/}]:-}" ]; then
    KEEP_REASON="an installed IDE uses it"
    return 0
  fi
  for sub in scratches consoles; do
    if [ -n "$(/usr/bin/find "$1/$sub" -type f -print -quit 2>/dev/null)" ]; then
      KEEP_REASON="holds $sub"
      KEEP_PARTIAL=plugins
      return 0
    fi
  done
  return 1
}

# Parsed in bash, not grep/awk: a missing tool must not silently empty the set
# and so allow deleting an installed IDE's settings.
add_product_info() {
  local line re='"dataDirectoryName"[[:space:]]*:[[:space:]]*"([^"]+)"'
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $re ]]; then INSTALLED_IDE_DIRS[${BASH_REMATCH[1]}]=1; fi
  done <"$1"
}

# IFS is empty so a glob with a space ("Application Support") still expands as
# one pattern: no word splitting, pathname expansion only.
load_installed_ides() {
  local glob f app IFS=
  for glob in "${IDE_PRODUCT_INFO_GLOBS[@]}"; do
    for f in $glob; do add_product_info "$f"; done
  done
  while read -r app; do
    add_product_info "$app/Contents/Resources/product-info.json"
  done < <(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "com.jetbrains.*"' 2>/dev/null || true)
}

# Per group (RANKFN), the highest-ranked dir under PARENT is kept. Each older
# one is kept when GUARDFN names a reason, else age-gated by consider. A guard
# may also set KEEP_PARTIAL, a subdir of the kept dir that is still age-gated.
scan_keep_newest() {
  local parent="$1" rankfn="$2" guardfn="${3:-}" d
  local -a dirs=()
  local -A newest=() rank_of=() group_of=()
  [ -d "$parent" ] || return 0
  for d in "$parent"/*; do
    [ -d "$d" ] || continue
    "$rankfn" "$d" || continue
    dirs+=("$d")
    rank_of[$d]=$RANK
    group_of[$d]=$RANK_GROUP
    if [ "$RANK" -gt "${newest[$RANK_GROUP]:--1}" ]; then newest[$RANK_GROUP]=$RANK; fi
  done
  for d in "${dirs[@]}"; do
    if [ "${rank_of[$d]}" -ge "${newest[${group_of[$d]}]}" ]; then
      log_verbose "  skip    (newest ${group_of[$d]})  $d"
    else
      KEEP_REASON="" KEEP_PARTIAL=""
      if [ -n "$guardfn" ] && "$guardfn" "$d"; then
        log_verbose "  skip    ($KEEP_REASON)  $d"
        # Symlinks are left alone: rm -rf would go through a linked version dir.
        if [ -n "$KEEP_PARTIAL" ] && [ -d "$d/$KEEP_PARTIAL" ] && [ ! -L "$d" ] && [ ! -L "$d/$KEEP_PARTIAL" ]; then
          consider "$d/$KEEP_PARTIAL"
        fi
      else
        consider "$d"
      fi
    fi
  done
}

scan_superseded() {
  local parent
  if [ -d "$JETBRAINS_SETTINGS" ]; then
    load_installed_ides
    scan_keep_newest "$JETBRAINS_SETTINGS" jetbrains_rank jetbrains_keep
  fi
  for parent in "${DEVICE_SUPPORT_PARENTS[@]}"; do
    scan_keep_newest "$parent" device_support_rank
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

# uv holds its cache lock for as long as any `uv run` lives (a dev server can
# run for weeks) and waits 300s for it by default; activation must not stall on
# that, so give up after 5s. Never --force: that prunes a cache in use.
gc_command() {
  case "$1" in
    uv) UV_LOCK_TIMEOUT=5 uv cache prune ;;
    pip3) pip3 cache purge ;;
    npm) npm cache clean --force ;;
    yarn) yarn cache clean ;;
    pnpm) pnpm store prune ;;
    bun) bun_cache_rm ;;
    go) go clean -cache ;;
    go-mod) go clean -modcache ;;
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
  local bin tool dir idle gated sz after freed failed reason
  PATH="/opt/homebrew/bin:$HOME/.local/share/mise/shims:$PATH"
  export PATH
  # A mise shim errors ("not currently active") outside a dir with a mise
  # config, and activation's cwd has none; $HOME resolves to the global config.
  cd "$HOME"
  # go-mod before go: wiping the build cache refreshes its mtime, which go-mod reads.
  for bin in uv pip3 npm yarn pnpm bun go-mod go; do
    # tool: the binary that runs the GC. gated=1: GC empties the whole cache, so
    # wait until it has sat idle. Go's cache dirs come from `go env`, which also
    # reads `go env -w` settings: the idle check must look at the dir that
    # `go clean` will really wipe.
    tool="$bin" idle=""
    case "$bin" in
      uv) dir="$HOME/.cache/uv" gated=0 ;;
      pip3) dir="$HOME/Library/Caches/pip" gated=1 ;;
      npm) dir="$HOME/.npm" gated=1 ;;
      yarn) dir="$HOME/Library/Caches/Yarn" gated=1 ;;
      pnpm) dir="$HOME/Library/pnpm/store" gated=0 ;;
      bun) dir="$HOME/.bun/install/cache" gated=1 ;;
      go)
        gated=1
        dir=$(go env GOCACHE 2>/dev/null || true)
        ;;
      go-mod)
        # Go never touches module files on a read, so the module cache cannot show
        # use; any `go build` does touch the build cache, so that one judges it.
        tool=go gated=1
        dir=$(go env GOMODCACHE 2>/dev/null || true)
        idle=$(go env GOCACHE 2>/dev/null || true)
        ;;
      *) dir="" gated=0 ;;
    esac
    idle="${idle:-$dir}"
    command -v "$tool" >/dev/null 2>&1 || continue
    if [ "$gated" -eq 1 ]; then
      # A cache that is gone (a wipe, or never created) has nothing to collect.
      [ -e "$dir" ] || continue
      if ! is_stale "$idle"; then
        if [ "$QUIET" -eq 0 ]; then
          log "  GC skip $(kb_to_human "$(dir_size_kb "$dir")")  $bin  (cache used within ${STALE_DAYS}d: $dir)"
        fi
        continue
      fi
    fi
    sz=$(dir_size_kb "$dir")
    if [ "$MODE" = "dry" ]; then
      log "  GC      $(kb_to_human "$sz")  $bin  (cache: $dir)"
      continue
    fi
    failed=0
    if ! gc_command "$bin" >/dev/null 2>&1; then
      # uv keeps its cache lock open for as long as a `uv run` lives; ask lsof
      # who holds it instead of guessing from the error text.
      reason=""
      if [ "$bin" = uv ] && /usr/sbin/lsof -- "$dir/.lock" >/dev/null 2>&1; then
        reason=" (cache locked)"
      fi
      gc_failed="${gc_failed:+$gc_failed, }$bin$reason"
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
log_verbose "-- superseded versions (JetBrains settings, Xcode DeviceSupport) --"
scan_superseded
log_verbose "-- dev tree ($DEV_ROOT) --"
scan_dev_tree

if [ "$MODE" != "dry" ]; then
  apply_deletes
fi

summary
