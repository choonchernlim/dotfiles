# Tool-version feature module: mise replaces nvm (node) and tfenv (terraform);
# would also cover java if it ever returns. Selected per-host via hosts/*.nix.
# Tool versions are declared in home/.config/mise/config.toml (live-symlinked);
# the zsh hook costs ~5ms vs the ~4s the retired nvm+sdkman init scripts took.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home = {
    file.".config/mise/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/mise/config.toml";

    # Cleanup from the Ansible nvm/sdkman role port (dev toolchain rewrite):
    # nvm/tfenv -> mise, sdkman/java/maven dropped. Idempotent; converges any
    # drifted machine on every rebuild.
    activation.miseReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "$HOME/.zshrc_conf/nvm.sh" "$HOME/.zshrc_conf/sdkman.sh" \
        "$HOME/.zshrc_conf/tfenv.sh" || true
      [ -d "$HOME/.sdkman" ] && rm -rf "$HOME/.sdkman" || true
      [ -d "$HOME/.nvm" ] && rm -rf "$HOME/.nvm" || true

      # home-manager backs up a pre-existing mise config as .hm-bak when it
      # first takes over the path.
      rm -f "$HOME/.config/mise/config.toml.hm-bak" || true

      # Retired brews; cleanup="none" never uninstalls, so reconcile does.
      # react-native-cli: deprecated upstream, undeclared drift; must go
      # before node (brew refuses to remove node while it depends on it).
      _brew=/opt/homebrew/bin/brew
      if [ -x "$_brew" ]; then
        for _pkg in nvm react-native-cli node maven tfenv; do
          "$_brew" list --formula "$_pkg" >/dev/null 2>&1 && \
            "$_brew" uninstall "$_pkg" || true
        done
      fi

      # Provision the mise-declared tools (node, terraform) so a bare rebuild
      # yields a working toolchain. No-op when versions are already installed.
      if [ -x "${pkgs.mise}/bin/mise" ]; then
        ${pkgs.mise}/bin/mise install --yes 2>/dev/null || true
      fi
    '';
  };

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };
}
