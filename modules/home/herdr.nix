# herdr plugins: declared here, installed on rebuild, and anything undeclared removed. herdr's plugin state
# (plugins.json and the plugin checkouts) is runtime state under the gitignored
# part of home/.config/herdr/, so the declaration below is the only thing that
# travels between hosts. Also ships `herdr-worktree-clean` (see below).
# Selected per-host via hosts/*.nix (hosts with the herdr cask).
{
  config,
  pkgs,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };

  # owner/repo, pinned to a commit so every host builds the same plugin.
  plugins = [
    {
      id = "persiyanov.reviewr";
      repo = "persiyanov/herdr-reviewr";
      ref = "859dd5b11a5280fe282de56b52378b20a54fa10a";
    }
  ];

  installLines = lib.concatMapStringsSep "\n" (p: ''
    install_plugin ${lib.escapeShellArg p.id} ${lib.escapeShellArg p.repo} ${lib.escapeShellArg p.ref}
  '') plugins;

  # Removes every linked worktree of the current directory's repo; the main
  # checkout and all branches are kept (herdr's `worktree remove` runs `git
  # worktree remove` and never deletes the branch). herdr and git come from the
  # user's PATH: herdr is a cask, and the git fallback should be the same git
  # that herdr itself runs.
  herdrWorktreeClean = pkgs.writeShellApplication {
    name = "herdr-worktree-clean";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      usage() {
        echo "usage: herdr-worktree-clean [--force]"
        echo "Removes every linked worktree of the current repo; keeps the main checkout and all branches."
        echo "  --force  also remove worktrees with uncommitted changes or commits on no branch (they are lost)"
        echo "Ignored files (.env, node_modules, ...) are always removed with their worktree."
      }
      force=()
      case "$*" in
        "") ;;
        --force) force=(--force) ;;
        -h | --help)
          usage
          exit 0
          ;;
        *)
          echo "herdr-worktree-clean: unknown argument: $*" >&2
          usage >&2
          exit 2
          ;;
      esac

      list=$(herdr worktree list --cwd "$PWD")
      # A changed herdr JSON shape must not read as "nothing to clean".
      if ! repo_root=$(jq -er .result.source.repo_root <<<"$list") \
        || ! jq -e '.result.worktrees | type == "array"' <<<"$list" >/dev/null; then
        echo "herdr-worktree-clean: unexpected 'herdr worktree list' output" >&2
        exit 1
      fi
      here=$(pwd -P)
      removed=()
      skipped=()
      failed=()

      # dirt PATH DETACHED: what removing PATH without --force would lose, empty
      # when nothing. --untracked-files=all overrides a status.showUntrackedFiles
      # that would hide untracked files (git's own remove guard honours it), and
      # a detached HEAD's commits on no branch die with the worktree's reflog.
      dirt() {
        local out
        out=$(git -C "$1" status --porcelain --untracked-files=all) || return 1
        if [ -n "$out" ]; then
          echo "uncommitted changes"
        elif [ "$2" = true ]; then
          out=$(git -C "$1" rev-list -n1 HEAD --not --branches --tags --remotes) || return 1
          if [ -n "$out" ]; then
            echo "commits on no branch"
          fi
        fi
      }

      # herdr can only remove a worktree open as a workspace; the rest go through
      # git. Prunable ones (folder already gone) are left to the prune below.
      # NUL-separated: jq's @tsv escapes tabs, newlines and backslashes in paths.
      while IFS= read -r -d "" path && IFS= read -r -d "" branch \
        && IFS= read -r -d "" detached && IFS= read -r -d "" workspace; do
        label="$path ($branch)"
        real=$(cd "$path" && pwd -P) || real=$path
        # Removing this shell's worktree or herdr workspace would pull its cwd
        # away or kill this script (a workspace keeps its id after a cd away).
        case "$here/" in "$real"/*)
          skipped+=("$label: contains the current directory")
          continue
          ;;
        esac
        if [ -n "$workspace" ] && [ "$workspace" = "''${HERDR_WORKSPACE_ID:-}" ]; then
          skipped+=("$label: is this shell's herdr workspace")
          continue
        fi
        if [ ''${#force[@]} -eq 0 ]; then
          if ! why=$(dirt "$path" "$detached"); then
            failed+=("$label: git could not read its state")
            continue
          fi
          if [ -n "$why" ]; then
            skipped+=("$label: $why (--force discards them)")
            continue
          fi
        fi
        if [ -n "$workspace" ]; then
          remove=(herdr worktree remove --workspace "$workspace" "''${force[@]}")
        else
          remove=(git -C "$repo_root" worktree remove "''${force[@]}" "$path")
        fi
        if "''${remove[@]}" >/dev/null </dev/null; then
          removed+=("$label")
        else
          failed+=("$label")
        fi
      done < <(jq -j '.result.worktrees[]
        | select(.is_linked_worktree and (.is_prunable | not) and (.path // "") != "")
        | [.path, (.branch // "detached"), (.is_detached | tostring), (.open_workspace_id // "")]
        | map(. + "\u0000") | add' <<<"$list")

      git -C "$repo_root" worktree prune --verbose

      report() {
        local title=$1
        shift
        if [ $# -gt 0 ]; then
          echo "$title:"
          printf '  %s\n' "$@"
        fi
      }
      report "Removed" "''${removed[@]}"
      report "Skipped" "''${skipped[@]}"
      report "Failed" "''${failed[@]}"
      problems=$((''${#skipped[@]} + ''${#failed[@]}))
      if [ $((''${#removed[@]} + problems)) -eq 0 ]; then
        echo "herdr-worktree-clean: no linked worktrees in $repo_root"
      fi
      [ "$problems" -eq 0 ]
    '';
  };
in

{
  home.packages = [ herdrWorktreeClean ];

  # herdr is a Homebrew cask, not a nix package, so it is referenced by absolute
  # path. Best-effort: a missing cask, offline rebuild, or failed plugin build
  # must not fail the rebuild (the next rebuild retries), but every skip or
  # failure is reported on stderr so a host missing a plugin is diagnosable.
  home.activation.herdrPluginsSetup = mkReconcile {
    name = "herdr-plugins-setup";
    text = ''
      herdr=/opt/homebrew/bin/herdr
      if [ ! -x "$herdr" ]; then
        echo "herdr-plugins-setup: $herdr not found, skipping plugin install" >&2
        exit 0
      fi

      # herdr shells out to git and the plugin's build script, and neither is on
      # the hermetic activation PATH (os error 2). /usr/bin/git validates TLS
      # against the Keychain; ${"$"}{pkgs.git} would not (see zscaler.nix).
      export PATH="$PATH:/usr/bin:/bin"

      # herdr records absolute paths, so a moved checkout or dev root leaves a
      # plugin registered but unloadable ("manifest unavailable"). Health is
      # therefore judged on the recorded manifest, not on the id being listed.
      # A failed listing skips the run rather than reinstalling everything.
      installed=$("$herdr" plugin list --json 2>/dev/null) || {
        echo "herdr-plugins-setup: could not list plugins, skipping" >&2
        exit 0
      }

      # field ID JQ_PATH: a field of the registered plugin ID; empty when unregistered.
      field() {
        printf '%s' "$installed" \
          | jq -r --arg id "$1" ".result.plugins[]? | select(.plugin_id == \$id) | $2 // empty"
      }

      # install_plugin ID REPO REF: (re)installs the pinned commit unless it is
      # registered at that commit with its manifest on disk, then always enables
      # it (a no-op when already enabled), so the plugin is installed and
      # enabled on every host after a rebuild.
      install_plugin() {
        _manifest=$(field "$1" .manifest_path)
        if [ ! -f "$_manifest" ] || [ "$(field "$1" .source.resolved_commit)" != "$3" ]; then
          if [ -n "$_manifest" ]; then
            "$herdr" plugin uninstall "$1" >/dev/null \
              || echo "herdr-plugins-setup: could not uninstall stale $1" >&2
          fi
          "$herdr" plugin install --yes --ref "$3" "$2" \
            || echo "herdr-plugins-setup: install of $2@$3 failed; rerun rebuild or see 'herdr plugin log list --plugin $1'" >&2
        fi
        "$herdr" plugin enable "$1" >/dev/null \
          || echo "herdr-plugins-setup: could not enable $1" >&2
      }

      ${installLines}

      # Every declared id, for the prune at the end; local plugins add theirs below.
      _keep=(${lib.concatMapStringsSep " " (p: lib.escapeShellArg p.id) plugins})

      # Every home/herdr-plugins/<dir>/ with a manifest is a local plugin, linked
      # from the live checkout so script edits apply without a rebuild. Relink
      # when the recorded manifest is not the live checkout's (herdr records the
      # resolved path; ~/.dotfiles is a symlink) or its version moved on: herdr
      # snapshots the manifest at link time, so bump `version` to roll out edits.
      _local_root=${lib.escapeShellArg "${dotfiles}/home/herdr-plugins"}
      [ -d "$_local_root" ] \
        || echo "herdr-plugins-setup: $_local_root missing, skipping local plugins" >&2
      _unparsed=0
      for _local_dir in "$_local_root"/*/; do
        _resolved=$(cd "$_local_dir" 2>/dev/null && pwd -P) || continue
        _local_manifest="$_resolved/herdr-plugin.toml"
        [ -f "$_local_manifest" ] || continue
        # First top-level match only; an unparsable version skips the version check
        # rather than relinking on every rebuild.
        _local_id=$(sed -n '/^id = /{s/^id = "\(.*\)"$/\1/p;q;}' "$_local_manifest")
        _local_version=$(sed -n '/^version = /{s/^version = "\(.*\)"$/\1/p;q;}' "$_local_manifest")
        if [ -z "$_local_id" ]; then
          echo "herdr-plugins-setup: no id in $_local_manifest, skipping it and the prune" >&2
          _unparsed=1
          continue
        fi
        _keep+=("$_local_id")
        if [ "$(field "$_local_id" .manifest_path)" != "$_local_manifest" ] \
          || { [ -n "$_local_version" ] && [ "$(field "$_local_id" .version)" != "$_local_version" ]; }; then
          if [ -n "$(field "$_local_id" .plugin_id)" ]; then
            "$herdr" plugin unlink "$_local_id" >/dev/null \
              || echo "herdr-plugins-setup: could not unlink stale $_local_id" >&2
          fi
          "$herdr" plugin link "$_resolved" \
            || echo "herdr-plugins-setup: could not link $_resolved" >&2
        fi
      done

      # Keep-set prune, so dropping a plugin from `plugins` or deleting or
      # renaming a local plugin dir takes effect on every host. The listing from
      # the start still holds every undeclared plugin (the steps above only
      # register declared ids). Skipped without the local root, or when a local
      # manifest's id could not be read: that plugin would look undeclared.
      if [ ! -d "$_local_root" ] || [ "$_unparsed" = 1 ]; then
        exit 0
      fi
      printf '%s' "$installed" \
        | jq -r --args '.result.plugins[]?
            | select(.plugin_id != null and (.plugin_id | IN($ARGS.positional[]) | not))
            | [.plugin_id, .source.kind] | @tsv' "''${_keep[@]}" \
        | while IFS=$'\t' read -r _id _kind; do
          if [ "$_kind" = local ]; then _verb="unlink"; else _verb="uninstall"; fi
          # </dev/null: herdr must not read the rest of this loop's input.
          if "$herdr" plugin "$_verb" "$_id" >/dev/null </dev/null; then
            echo "herdr-plugins-setup: ''${_verb}ed undeclared plugin $_id" >&2
          else
            echo "herdr-plugins-setup: could not $_verb undeclared plugin $_id" >&2
          fi
        done
    '';
  };
}
