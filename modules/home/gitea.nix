# Gitea feature module: local git server (Gitea + Postgres) via Docker Compose,
# started manually with the gitea-up/gitea-down/gitea-status/gitea-logs shell
# functions - no launchd daemon of its own (colima's autostart lives in
# modules/home/colima.nix, kept generic/non-gitea-specific). Selected per-host
# via hosts/*.nix home imports (work, work-atdj only; the colima/docker/docker-compose
# runtime it depends on is declared in modules/darwin/homebrew/common.nix). Because
# colima autostarts at login and the compose services are `restart:
# unless-stopped`, gitea-up only needs to be run once ever (or again after a
# gitea-down) - the containers otherwise come back on their own.
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
    # Edit-in-place: the real compose file stays in my repo, ~/.config just
    # points at it.
    file.".config/gitea".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/gitea";

    activation.giteaReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "$HOME/.config/gitea/docker-compose.yml.hm-bak" || true
      [ -d "$HOME/.config/gitea.hm-bak" ] && rm -rf "$HOME/.config/gitea.hm-bak" || true
    '';
  };

  programs.zsh.initContent = lib.mkOrder 900 ''
    # colima/docker/docker-compose come from common.nix (shared by all hosts);
    # colima autostarts at login (modules/home/colima.nix), so this is normally
    # a no-op safety net. docker-compose is the standalone (hyphenated) formula -
    # the "docker compose" subcommand form isn't wired up by that formula, so
    # use this form throughout.
    _gitea_compose="$HOME/.config/gitea/docker-compose.yml"

    gitea-up() {
      colima status >/dev/null 2>&1 || colima start
      docker-compose -f "$_gitea_compose" up -d
      echo "Gitea: http://localhost:3100"
    }
    gitea-down() {
      docker-compose -f "$_gitea_compose" down
    }
    gitea-status() {
      docker-compose -f "$_gitea_compose" ps
    }
    gitea-logs() {
      docker-compose -f "$_gitea_compose" logs -f
    }
  '';
}
