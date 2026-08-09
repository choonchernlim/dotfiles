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
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in

{
  home = {
    file.".config/mise/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/mise/config.toml";

    # Provision the mise-declared tools (node, terraform) so a bare rebuild
    # yields a working toolchain. No-op when versions are already installed;
    # best-effort (|| true) so an offline rebuild still succeeds. (Ansible-era
    # nvm/sdkman cleanup moved to legacy.nix; retired brews are removed by
    # cleanup = "zap".)
    activation.miseSetup = mkReconcile {
      name = "mise-setup";
      path = [ pkgs.mise ];
      text = ''
        mise install --yes 2>/dev/null || true
      '';
    };
  };

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };
}
