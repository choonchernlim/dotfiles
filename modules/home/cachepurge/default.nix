# Cache-purge feature module: reclaims disk space from stale tool caches and
# dev-tree build artifacts. Selected per-host via hosts/*.nix (all 3 hosts; the
# script no-ops where ~/Documents/development doesn't exist).
#
# `cache-purge` is a real command (home.packages) with three modes:
#   (no flag)  dry run: report what would be reclaimed, delete nothing
#   --apply    reclaim now, ignoring the free-space gate
#   --auto     used by the activation below: only proceeds when free space is
#              below the 100G gate; the 14-day staleness gate always applies
#
# The script itself is ./cache-purge.sh - plain bash, shellcheck-gated at build
# time by writeShellApplication. Its safety rules are documented in its header.
#
# `brew cleanup` is deliberately not part of this: modules/darwin/homebrew's
# brewMaintenance activation owns that.
{
  pkgs,
  lib,
  ...
}:

let
  mkReconcile = import ../lib/reconcile.nix { inherit pkgs lib; };

  cachePurge = pkgs.writeShellApplication {
    name = "cache-purge";
    # gawk: du/df output is piped through awk; not on the hermetic activation PATH.
    runtimeInputs = [ pkgs.gawk ];
    text = builtins.readFile ./cache-purge.sh;
  };
in
{
  home.packages = [ cachePurge ];

  # CACHE_PURGE=off is the escape hatch, forwarded through sudo by rebuild.sh's
  # --preserve-env=CACHE_PURGE (sudo's env_reset would otherwise drop it).
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
