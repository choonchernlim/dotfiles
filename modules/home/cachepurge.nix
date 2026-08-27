# Cache-purge feature module: reclaims disk space from home tool caches and
# dev-tree build artifacts. Selected per-host via hosts/*.nix home imports
# (work, personal, work-atdj - all 3 hosts; the script no-ops if
# ~/Documents/development doesn't exist, so importing it on a host without
# that dev tree is harmless).
#
# `cache-purge` is a real command (home.packages) with three modes:
#   (no flag)  dry run: report what would be reclaimed, delete nothing
#   --apply    reclaim now, ignoring the free-space gate
#   --auto     used by the activation reconcile below: only proceeds when
#              free space is below the 100G gate; the 14-day staleness gate
#              always applies, in every mode
#
# Safety, by design (see discussion.md and the accompanying plan for the
# full writeup):
#   - tool-native GC (`uv cache prune`, `pip3 cache purge`, ...) runs first;
#     only caches with no such command are ever deleted directly.
#   - direct deletes are scoped to an explicit allowlist of cache
#     directories, or to a fixed set of build-artifact names inside
#     ~/Documents/development - never a blanket sweep.
#   - staleness is checked by recursively probing for ANY file modified in
#     the last 14 days, never a directory's own top-level mtime - that
#     signal is wrong (~/Library/Caches/JetBrains/IntelliJIdea2026.2 has an
#     old top-level mtime but is written to daily).
#   - the dev-tree walk prunes at node_modules/.venv/venv/.git and never
#     deletes anything literally named dist/build/coverage - those names
#     collide with real installed package dirs (site-packages/coverage) and
#     with thousands of node_modules-internal dist/build dirs on this
#     machine (discussion.md's original find/rm snippet had this bug).
#   - a .terraform/ directory containing an `environment` file (a selected
#     non-default workspace) is skipped - deleting it would silently revert
#     `terraform init` back to the default workspace.
#   - find is always invoked as /usr/bin/find: the interactive shell's PATH
#     resolves `find` to bfs, which errors on a -newermt staleness probe,
#     and GNU find's flags differ from BSD's - pinning the absolute path
#     keeps behavior identical regardless of what's first on PATH.
#
# `brew cleanup` is deliberately NOT part of this module - modules/darwin/
# default.nix's brewMaintenance activation already owns that.
{
  pkgs,
  lib,
  ...
}:

let
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };

  cachePurge = pkgs.writeShellApplication {
    name = "cache-purge";
    # gawk: du/df output is piped through awk for field extraction and for
    # the human-readable size formatting - not on the hermetic activation
    # PATH by default (see reconcile.nix's header for the prior incident
    # this exact gap caused).
    runtimeInputs = [ pkgs.gawk ];
    text = ''
      STALE_DAYS=14
      FREE_GATE_KB=$((100 * 1024 * 1024)) # 100G, in the 1K blocks df -k reports
      DEV_ROOT="$HOME/Documents/development"

      # Age-gated cache dirs with no tool-native GC command. Staleness is
      # checked per immediate child (each JetBrains IDE version, each
      # playwright chromium build, ...), never on the parent as a whole.
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

      total_reclaimed_kb=0
      to_delete=()

      log() { printf '%s\n' "$*"; }

      # Always succeeds, even if the path is missing or du fails on it
      # (permissions, etc.) - sizing must never abort the whole run.
      dir_size_kb() {
        local d="$1" out=""
        if [ -e "$d" ]; then
          out=$(du -sk "$d" 2>/dev/null | awk '{print $1}') || out=""
        fi
        printf '%s' "''${out:-0}"
      }

      kb_to_human() {
        awk -v kb="$1" 'BEGIN { printf "%.1fG", kb / 1024 / 1024 }'
      }

      # True (0) if DIR contains no file modified within STALE_DAYS. Probes
      # recursively rather than trusting DIR's own mtime - see the module
      # header for why - and is always invoked via /usr/bin/find, since the
      # ambient PATH's `find` is bfs on this machine and rejects -newermt.
      is_stale() {
        local dir="$1"
        [ -e "$dir" ] || return 1
        if [ -n "$(/usr/bin/find "$dir" -mtime "-''${STALE_DAYS}" -print -quit 2>/dev/null)" ]; then
          return 1
        fi
        return 0
      }

      # Records PATH in to_delete + the running total when stale; otherwise
      # just logs it as active, so a dry run shows exactly what would be
      # excluded and why.
      consider() {
        local path="$1" sz
        sz=$(dir_size_kb "$path")
        if is_stale "$path"; then
          log "  STALE   $(kb_to_human "$sz")  $path"
          to_delete+=("$path")
          total_reclaimed_kb=$((total_reclaimed_kb + sz))
        else
          log "  active  $(kb_to_human "$sz")  $path"
        fi
      }

      scan_age_gated() {
        local parent child
        for parent in "''${AGE_GATED_PARENTS[@]}"; do
          [ -d "$parent" ] || continue
          while IFS= read -r -d "" child; do
            consider "$child"
          done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 -print0)
        done
      }

      scan_dev_tree() {
        [ -d "$DEV_ROOT" ] || return 0
        local hit
        while IFS= read -r -d "" hit; do
          if [ "$(basename "$hit")" = ".terraform" ] && [ -e "$hit/environment" ]; then
            log "  skip    (workspace selected)  $hit"
            continue
          fi
          consider "$hit"
        done < <(/usr/bin/find "$DEV_ROOT" \
          \( -name node_modules -o -name .venv -o -name venv -o -name .git \) -prune -o \
          -type d \( -name .next -o -name .wireit -o -name __pycache__ \
            -o -name .pytest_cache -o -name .mypy_cache -o -name .ruff_cache \
            -o -name htmlcov -o -name .turbo -o -name .terraform \) \
          -print0 -prune)
      }

      # Tool-native GC: tried first, run unconditionally in apply/auto mode -
      # each tool decides what's still referenced, so no age gate is needed.
      # PATH is extended here rather than left to the caller: uv/bun/go are
      # homebrew, npm/pnpm/yarn are mise shims, and work-atdj has no mise at
      # all, so this must work whether or not either is already on PATH.
      run_tool_gc() {
        local bin dir sz
        PATH="/opt/homebrew/bin:$HOME/.local/share/mise/shims:$PATH"
        export PATH
        for bin in uv pip3 npm yarn pnpm bun go; do
          command -v "$bin" >/dev/null 2>&1 || continue
          case "$bin" in
            uv) dir="$HOME/.cache/uv" ;;
            pip3) dir="$HOME/Library/Caches/pip" ;;
            npm) dir="$HOME/.npm" ;;
            yarn) dir="$HOME/Library/Caches/Yarn" ;;
            pnpm) dir="$HOME/Library/pnpm/store" ;;
            bun) dir="$HOME/.bun/install/cache" ;;
            go) dir="$HOME/Library/Caches/go-build" ;;
            *) dir="" ;;
          esac
          sz=$(dir_size_kb "$dir")
          if [ "$MODE" = "dry" ]; then
            log "  GC      $(kb_to_human "$sz")  $bin  (cache: $dir)"
            continue
          fi
          log "  GC      running: $bin"
          case "$bin" in
            uv) uv cache prune >/dev/null 2>&1 || true ;;
            pip3) pip3 cache purge >/dev/null 2>&1 || true ;;
            npm) npm cache clean --force >/dev/null 2>&1 || true ;;
            yarn) yarn cache clean >/dev/null 2>&1 || true ;;
            pnpm) pnpm store prune >/dev/null 2>&1 || true ;;
            bun) bun pm cache rm >/dev/null 2>&1 || true ;;
            go) go clean -cache >/dev/null 2>&1 || true ;;
          esac
          total_reclaimed_kb=$((total_reclaimed_kb + sz))
        done
      }

      apply_deletes() {
        local p
        for p in "''${to_delete[@]}"; do
          rm -rf -- "$p"
        done
      }

      MODE="dry"
      case "''${1:-}" in
        --apply) MODE="apply" ;;
        --auto) MODE="auto" ;;
        -h | --help)
          log "usage: cache-purge [--apply|--auto]"
          log "  (no flag)  dry run: report what would be reclaimed, delete nothing"
          log "  --apply    reclaim now, ignoring the free-space gate"
          log "  --auto     used by the rebuild activation: only proceeds when free"
          log "             space is below the gate; the 14-day staleness gate"
          log "             always applies, in every mode"
          exit 0
          ;;
        "") ;;
        *)
          echo "cache-purge: unknown argument: $1" >&2
          exit 1
          ;;
      esac

      if [ "$MODE" = "auto" ]; then
        free_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}') || free_kb=""
        free_kb="''${free_kb:-0}"
        if [ "$free_kb" -ge "$FREE_GATE_KB" ]; then
          exit 0
        fi
      fi

      log "cache-purge: mode=$MODE, staleness cutoff=''${STALE_DAYS}d"
      log "-- tool-native GC --"
      run_tool_gc
      log "-- home caches (age-gated allowlist) --"
      scan_age_gated
      log "-- dev tree ($DEV_ROOT) --"
      scan_dev_tree

      if [ "$MODE" != "dry" ]; then
        apply_deletes
      fi

      log "cache-purge: reclaimed $(kb_to_human "$total_reclaimed_kb")"
    '';
  };
in
{
  home.packages = [ cachePurge ];

  # CACHE_PURGE=off is the escape hatch, forwarded through sudo by
  # rebuild.sh's --preserve-env=CACHE_PURGE (sudo's env_reset would
  # otherwise drop it before darwin-rebuild ever runs this activation).
  home.activation.cachePurgeAuto = mkReconcile {
    name = "cache-purge-auto";
    path = [ cachePurge ];
    text = ''
      if [ "''${CACHE_PURGE:-}" = "off" ]; then
        echo "cache-purge: skipped (CACHE_PURGE=off)"
      else
        cache-purge --auto
      fi
    '';
  };
}
