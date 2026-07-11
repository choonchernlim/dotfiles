# QuickLook feature module: Finder preview plugins (ported from the Ansible
# quicklook role, pruned to the 4 upstream-maintained ones). Selected per-host
# via hosts/*.nix darwin imports.
#
# The plugin refresh and reconcile run as the user (brew/xattr/qlmanage refuse
# or misbehave under root), so they live in a home-manager activation that this
# darwin module contributes - keeping the whole feature in one file.
_:

{
  homebrew.casks = [
    "syntax-highlight" # code/markdown/json previews (obsoletes qlstephen, qlmarkdown, quicklook-json)
    "suspicious-package" # inspect .pkg installers
    "apparency" # inspect .app bundles
    "quicklook-video" # previews for non-native video formats
  ];

  home-manager.sharedModules = [
    (
      { lib, ... }:
      {
        home.activation.quicklookReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Catalina-era plugins dropped in the port - broken on modern macOS.
          _brew=/opt/homebrew/bin/brew
          if [ -x "$_brew" ]; then
            for _pkg in qlstephen qlmarkdown quicklook-json quicklookase; do
              "$_brew" list --cask "$_pkg" >/dev/null 2>&1 && \
                "$_brew" uninstall --cask "$_pkg" || true
            done
          fi

          # Ports the Ansible role's post-install steps: strip quarantine so
          # Finder loads the generators, then refresh the QuickLook registry.
          [ -d "$HOME/Library/QuickLook" ] && \
            /usr/bin/xattr -d -r com.apple.quarantine "$HOME/Library/QuickLook" 2>/dev/null || true
          /usr/bin/qlmanage -r >/dev/null 2>&1 || true
          /usr/bin/qlmanage -r cache >/dev/null 2>&1 || true
        '';
      }
    )
  ];
}
