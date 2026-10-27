# Zed feature module: the settings.json link and the declared-extensions prune.
# Selected per-host via hosts/*.nix home imports (work and personal: the hosts
# whose Homebrew list has the zed cask).
#
# The declared extensions are settings.json's auto_install_extensions, the one
# list Zed itself reads (see docs/gotchas.md). Biome's binary and its fallback
# config come from vscode.nix, which every Zed host also imports.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  settings = "${config.home.homeDirectory}/.dotfiles/home/zed/settings.json";
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in

{
  home = {
    # Only settings.json: keymap.json holds Zed's empty template, and the rest
    # of ~/.config/zed is Zed's runtime state.
    file.".config/zed/settings.json".source = config.lib.file.mkOutOfStoreSymlink settings;

    # Reads the live checkout, like the link. Fails safe: an unreadable file or
    # an empty list skips the prune, so a parse miss can never empty the store.
    # hjson-cli turns Zed's JSONC (comments, trailing commas) into JSON for jq.
    activation.zedExtensions = mkReconcile {
      name = "zed-extensions";
      path = [ pkgs.hjson-go ];
      text = ''
        _ext="$HOME/Library/Application Support/Zed/extensions"
        _dir="$_ext/installed"
        if [ ! -d "$_dir" ]; then
          echo "zed-extensions: no extensions dir yet, skipped" >&2
          exit 0
        fi
        # A false entry means "never install", so only true ones are kept.
        if ! _keep=$(hjson-cli -j ${lib.escapeShellArg settings} 2>/dev/null \
          | jq -c '[.auto_install_extensions // {} | to_entries[] | select(.value == true and .key != "") | .key]'); then
          echo "zed-extensions: cannot read settings.json, skipped" >&2
          exit 0
        fi
        if [ "$_keep" = "[]" ]; then
          echo "zed-extensions: no declared extensions, skipped" >&2
          exit 0
        fi

        # A glob, not find | read: an entry name may hold a newline.
        declare -A _kept
        while IFS= read -r _id; do _kept[$_id]=1; done < <(jq -r '.[]' <<< "$_keep")
        # A symlink is a dev extension (Zed's "install dev extension"): kept.
        # work/<id> holds the extension's downloaded servers; Zed's own
        # uninstall deletes it too.
        for _path in "$_dir"/*; do
          [ -d "$_path" ] && [ ! -L "$_path" ] || continue
          _id=''${_path##*/}
          [ -n "''${_kept[$_id]+x}" ] && continue
          rm -rf -- "$_path" "$_ext/work/$_id" && echo "zed-extensions: removed $_id"
        done
      '';
    };
  };
}
