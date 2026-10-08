# herdr plugins: declared here, installed on rebuild. herdr's plugin state
# (plugins.json and the plugin checkouts) is runtime state under the gitignored
# part of home/.config/herdr/, so the declaration below is the only thing that
# travels between hosts. Selected per-host via hosts/*.nix (hosts with the herdr cask).
{ pkgs, lib, ... }:

let
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };

  # owner/repo, pinned to a commit so every host builds the same plugin.
  plugins = [
    {
      repo = "persiyanov/herdr-reviewr";
      ref = "859dd5b11a5280fe282de56b52378b20a54fa10a";
    }
  ];

  installLines = lib.concatMapStringsSep "\n" (p: ''
    install_plugin ${lib.escapeShellArg p.repo} ${lib.escapeShellArg p.ref}
  '') plugins;
in

{
  # herdr is a Homebrew cask, not a nix package, so it is referenced by absolute
  # path. Best-effort: a missing cask, offline rebuild, or failed plugin build
  # must not fail the rebuild; the next rebuild retries.
  home.activation.herdrPluginsSetup = mkReconcile {
    name = "herdr-plugins-setup";
    text = ''
      herdr=/opt/homebrew/bin/herdr
      [ -x "$herdr" ] || exit 0

      installed=$("$herdr" plugin list 2>/dev/null || true)

      # Skips a plugin whose pinned commit is already installed.
      install_plugin() {
        case "$installed" in
          *"github:''${1}@''${2}"*) return 0 ;;
        esac
        "$herdr" plugin install --yes --ref "$2" "$1" || true
      }

      ${installLines}
    '';
  };
}
