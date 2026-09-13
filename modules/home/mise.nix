# Tool-version feature module: mise manages java, node, and terraform.
# Selected per-host via hosts/*.nix (work and personal, not work-atdj).
# Versions are declared in home/.config/mise/config.toml (live-symlinked).
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

    # Provision the declared tools so a bare rebuild yields a working toolchain.
    # No-op when already installed; best-effort so an offline rebuild still succeeds.
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
