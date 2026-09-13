# Gitea feature module: local git server (Gitea + Postgres) via Docker Compose,
# driven by the gitea-up/-down/-status/-logs shell functions. Selected per-host
# via hosts/*.nix (work, work-atdj). Colima autostarts at login (colima.nix) and
# the services are `restart: unless-stopped`, so gitea-up is needed once ever
# (or again after a gitea-down).
{
  config,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  # Edit-in-place: the compose file stays in the repo, ~/.config points at it.
  home.file.".config/gitea".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/gitea";

  programs.zsh.initContent = lib.mkOrder 900 ''
    # docker-compose is the standalone (hyphenated) formula from common.nix;
    # the `docker compose` subcommand form is not wired up by it.
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
