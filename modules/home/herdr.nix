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

      installed=$("$herdr" plugin list 2>/dev/null || true)

      # install_plugin ID REPO REF: installs the pinned commit unless already
      # present, then always enables it (a no-op when already enabled), so the
      # plugin is installed and enabled on every host after a rebuild.
      install_plugin() {
        case "$installed" in
          *"github:''${2}@''${3}"*) ;;
          *)
            "$herdr" plugin install --yes --ref "$3" "$2" \
              || echo "herdr-plugins-setup: install of $2@$3 failed; rerun rebuild or see 'herdr plugin log $1'" >&2
            ;;
        esac
        "$herdr" plugin enable "$1" >/dev/null \
          || echo "herdr-plugins-setup: could not enable $1" >&2
      }

      ${installLines}

      # `plugin link` registers the path itself, so a plugin id already listed is skipped.
      case "$installed" in
        *dotfiles.worktreeinclude*) ;;
        *) "$herdr" plugin link ${lib.escapeShellArg localPlugin} || true ;;
      esac
    '';
  };
}
