# QuickLook feature module: Finder preview plugins, pruned to the upstream-
# maintained ones. Selected per-host via hosts/*.nix darwin imports.
#
# The post-install refresh runs as the user (xattr/qlmanage misbehave under
# root), so it lives in a home-manager activation this darwin module
# contributes - keeping the whole feature in one file.
_:

{
  homebrew.casks = [
    "syntax-highlight" # code/markdown/json previews
    "suspicious-package" # inspect .pkg installers
    "apparency" # inspect .app bundles
    "quicklook-video" # previews for non-native video formats
  ];

  home-manager.sharedModules = [
    (
      { pkgs, lib, ... }:
      let
        mkReconcile = import ../home/lib/reconcile.nix { inherit pkgs lib; };
      in
      {
        # Strip quarantine so Finder loads the generators, then refresh the registry.
        home.activation.quicklookRefresh = mkReconcile {
          name = "quicklook-refresh";
          text = ''
            [ -d "$HOME/Library/QuickLook" ] && \
              /usr/bin/xattr -d -r com.apple.quarantine "$HOME/Library/QuickLook" 2>/dev/null || true
            /usr/bin/qlmanage -r >/dev/null 2>&1 || true
            /usr/bin/qlmanage -r cache >/dev/null 2>&1 || true
          '';
        };
      }
    )
  ];
}
