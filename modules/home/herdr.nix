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
            || echo "herdr-plugins-setup: install of $2@$3 failed; rerun rebuild or see 'herdr plugin log list --plugin $1'" >&2
        fi
        "$herdr" plugin enable "$1" >/dev/null \
          || echo "herdr-plugins-setup: could not enable $1" >&2
      }

      ${installLines}

      # Every home/herdr-plugins/<dir>/ with a manifest is a local plugin, linked
      # from the live checkout so script edits apply without a rebuild. Relink
      # when the recorded manifest is not the live checkout's (herdr records the
      # resolved path; ~/.dotfiles is a symlink) or its version moved on: herdr
      # snapshots the manifest at link time, so bump `version` to roll out edits.
      _local_root=${lib.escapeShellArg "${dotfiles}/home/herdr-plugins"}
      [ -d "$_local_root" ] \
        || echo "herdr-plugins-setup: $_local_root missing, skipping local plugins" >&2
      for _local_dir in "$_local_root"/*/; do
        _resolved=$(cd "$_local_dir" 2>/dev/null && pwd -P) || continue
        _local_manifest="$_resolved/herdr-plugin.toml"
        [ -f "$_local_manifest" ] || continue
        # First top-level match only; an unparsable version skips the version check
        # rather than relinking on every rebuild.
        _local_id=$(sed -n '/^id = /{s/^id = "\(.*\)"$/\1/p;q;}' "$_local_manifest")
        _local_version=$(sed -n '/^version = /{s/^version = "\(.*\)"$/\1/p;q;}' "$_local_manifest")
        if [ -z "$_local_id" ]; then
          echo "herdr-plugins-setup: no id in $_local_manifest, skipping" >&2
          continue
        fi
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
    '';
  };
}
