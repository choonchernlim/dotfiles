# Terminal feature module: ghostty config (live-symlinked) and terminal-domain
# cleanup. Selected per-host via hosts/*.nix home imports.
{
  config,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home = {
    # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
    file.".config/ghostty".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty";

    # Terminal-domain reconcile: converges any machine on every rebuild.
    activation.ghosttyReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # The Ansible ghostty role copied a real config file; home-manager backs
      # it up as .hm-bak when the symlink takes over. The dir variant appears
      # when ~/.config/ghostty itself was a real dir.
      rm -f "$HOME/.config/ghostty/config.hm-bak" || true
      rm -rf "$HOME/.config/ghostty.hm-bak" || true

      # iTerm2 dropped entirely - WezTerm + ghostty are the terminals. The
      # Ansible iterm2 role's DynamicProfiles/plist config dies with it.
      rm -rf "$HOME/Library/Application Support/iTerm2" || true
      rm -f "$HOME/Library/Preferences/com.googlecode.iterm2.plist" || true
      _brew=/opt/homebrew/bin/brew
      if [ -x "$_brew" ]; then
        "$_brew" list --cask iterm2 >/dev/null 2>&1 && \
          "$_brew" uninstall --cask iterm2 || true
      fi
    '';
  };
}
