# herdr plugins: declared here, installed on rebuild. herdr's plugin state
# (plugins.json and the plugin checkouts) is runtime state under the gitignored
# part of home/.config/herdr/, so the declaration below is the only thing that
# travels between hosts. Selected per-host via hosts/*.nix (hosts with the herdr cask).
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

  # Local plugin, linked from the live checkout so script edits apply without a
  # rebuild. It copies .worktreeinclude files into new worktrees, like `claude -w`.
  localPlugin = "${dotfiles}/home/herdr-plugins/worktreeinclude";

  installLines = lib.concatMapStringsSep "\n" (p: ''
    install_plugin ${lib.escapeShellArg p.id} ${lib.escapeShellArg p.repo} ${lib.escapeShellArg p.ref}
  '') plugins;
in

{
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
            || echo "herdr-plugins-setup: install of $2@$3 failed; rerun rebuild or see 'herdr plugin log $1'" >&2
        fi
        "$herdr" plugin enable "$1" >/dev/null \
          || echo "herdr-plugins-setup: could not enable $1" >&2
      }

      ${installLines}

      # `plugin link` registers the path itself, so it is relinked only when the
      # recorded manifest is not the live checkout's. herdr records the resolved
      # path (~/.dotfiles is a symlink), so compare against that.
      _local_id=dotfiles.worktreeinclude
      _local_dir=${lib.escapeShellArg localPlugin}
      if _resolved=$(cd "$_local_dir" 2>/dev/null && pwd -P); then
        _local_manifest="$_resolved/herdr-plugin.toml"
        if [ "$(field "$_local_id" .manifest_path)" != "$_local_manifest" ] || [ ! -f "$_local_manifest" ]; then
          if [ -n "$(field "$_local_id" .plugin_id)" ]; then
            "$herdr" plugin unlink "$_local_id" >/dev/null \
              || echo "herdr-plugins-setup: could not unlink stale $_local_id" >&2
          fi
          "$herdr" plugin link "$_local_dir" \
            || echo "herdr-plugins-setup: could not link $_local_dir" >&2
        fi
      else
        echo "herdr-plugins-setup: $_local_dir missing, skipping local plugin" >&2
      fi
    '';
  };
}
