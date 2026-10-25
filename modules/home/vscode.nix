# VS Code feature module: settings/keybindings/Biome-fallback links, biome + nixd
# packages, and the declared-extensions reconcile.
# Selected per-host via hosts/*.nix home imports (all 3 hosts; the cask is in
# homebrew/common.nix).
#
# Extensions are a list option so a host can append its own in hosts/<host>.nix;
# nix concatenates the definitions.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };

  # Marketplace IDs are case-insensitive; `code --list-extensions` prints the
  # publisher's casing, so both sides are compared lowercased.
  declared = builtins.toJSON (lib.unique (map lib.toLower config.dotfiles.vscode.extensions));
in

{
  options.dotfiles.vscode.extensions = lib.mkOption {
    # publisher.name only, so a typo, path, or `-`-prefixed string fails at
    # eval instead of becoming a CLI flag.
    type = lib.types.listOf (
      lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*\\.[A-Za-z0-9][A-Za-z0-9-]*"
    );
    default = [ ];
    example = [ "golang.go" ];
    description = "VS Code Marketplace extension IDs to keep installed; undeclared ones are uninstalled.";
  };

  config = {
    dotfiles.vscode.extensions = [
      # look
      "jdinhlife.gruvbox"
      # AI
      "anthropic.claude-code"
      # JS/TS: Biome formats + lints everywhere; ESLint/Prettier serve repos
      # configured for them. native-preview is the TS 7 (Go) language server.
      "biomejs.biome"
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "typescriptteam.native-preview"
      # Python: ty replaces Pylance (see docs/gotchas.md). python-envs finds
      # uv's .venv and creates environments with uv.
      "ms-python.python"
      "ms-python.debugpy"
      "ms-python.vscode-python-envs"
      "astral-sh.ty"
      "charliermarsh.ruff"
      # SAS
      "sas.sas-lsp"
      # editing
      "usernamehw.errorlens"
      # Same linter the flake checks run on every activation script.
      "timonwong.shellcheck"
      "editorconfig.editorconfig"
      "tamasfe.even-better-toml"
      "redhat.vscode-yaml"
      "jnoortheen.nix-ide"
    ];

    home = {
      packages = [
        # The Biome extension falls back to the biome on PATH in projects that
        # don't install @biomejs/biome; without one it does nothing there.
        pkgs.biome
        # Nix IDE's language server (nix.serverPath in settings.json).
        pkgs.nixd
      ];

      file = {
        # Only these two files: the rest of Code/User is VS Code's runtime state.
        "Library/Application Support/Code/User/settings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/vscode/settings.json";
        "Library/Application Support/Code/User/keybindings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/vscode/keybindings.json";
        # Biome's config for projects without their own; its built-in default
        # indents with tabs (docs/gotchas.md).
        "Library/Application Support/biome/biome.json".source =
          config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/biome/biome.json";
      };

      # Installs are networked, so they are best-effort: an offline rebuild
      # leaves the set as it was and the next one converges. No dependency
      # graph: VS Code itself refuses to uninstall an extension another one
      # depends on, which shows here as "could not remove" until it is declared.
      # Removing an undeclared extension pack also removes its members; a
      # declared one among them comes back on the next rebuild.
      activation.vscodeExtensions = mkReconcile {
        name = "vscode-extensions";
        text = ''
          _code=/opt/homebrew/bin/code
          if [ ! -x "$_code" ]; then
            echo "vscode-extensions: $_code not found, skipped" >&2
            exit 0
          fi
          _declared=${lib.escapeShellArg declared}
          # Installed IDs as a lowercased JSON array.
          _list() {
            "$_code" --list-extensions < /dev/null 2>/dev/null \
              | jq -R -s -c 'split("\n") | map(select(length > 0) | ascii_downcase)'
          }

          if ! _installed=$(_list); then
            echo "vscode-extensions: code --list-extensions failed, skipped" >&2
            exit 0
          fi

          _missing=$(jq -n -c --argjson d "$_declared" --argjson i "$_installed" '$d - $i')
          if [ "$_missing" != "[]" ]; then
            # One call: the CLI installs them in parallel and carries on past a
            # failure; its output (the reason) is shown only when one fails.
            mapfile -t _args < <(jq -r '.[] | ("--install-extension", .)' <<< "$_missing")
            if ! _out=$("$_code" "''${_args[@]}" < /dev/null 2>&1); then
              printf '%s\n' "$_out" >&2
            fi
            _installed=$(_list) || exit 0
            jq -r --argjson i "$_installed" '. - (. - $i) | .[] | "vscode-extensions: installed \(.)"' <<< "$_missing"
            jq -r --argjson i "$_installed" '. - $i | .[] | "vscode-extensions: could not install \(.)"' <<< "$_missing" >&2
            # A declared extension that is absent cannot protect its pack members
            # or dependencies from the removal pass; leave the set alone until it
            # installs.
            if [ "$(jq -n -c --argjson m "$_missing" --argjson i "$_installed" '$m - $i')" != "[]" ]; then
              echo "vscode-extensions: skipped removals" >&2
              exit 0
            fi
          fi

          _extra=$(jq -n -c --argjson d "$_declared" --argjson i "$_installed" '$i - $d')
          if [ "$_extra" != "[]" ]; then
            # One call here too: each `code` invocation is an Electron cold start.
            mapfile -t _args < <(jq -r '.[] | ("--uninstall-extension", .)' <<< "$_extra")
            if ! _out=$("$_code" "''${_args[@]}" < /dev/null 2>&1); then
              printf '%s\n' "$_out" >&2
            fi
            _installed=$(_list) || exit 0
            jq -r --argjson i "$_installed" '. - $i | .[] | "vscode-extensions: removed \(.)"' <<< "$_extra"
            jq -r --argjson i "$_installed" '. - (. - $i) | .[] | "vscode-extensions: could not remove \(.)"' <<< "$_extra" >&2
          fi
        '';
      };
    };
  };
}
