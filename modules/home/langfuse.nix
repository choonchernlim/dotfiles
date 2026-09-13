# Langfuse feature module: local observability stack via Docker Compose, driven
# by the langfuse-up/-down/-status/-logs shell functions. Selected by the work
# host only. Colima autostarts at login (colima.nix) and the services are
# `restart: always`, so langfuse-up is needed once on a fresh host.
{
  config,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  # Link only the compose file so the directory stays free for a user-owned
  # .env, never committed to this public repo.
  home.file.".config/langfuse/docker-compose.yml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/langfuse/docker-compose.yml";

  programs.zsh.initContent = lib.mkOrder 900 ''
    _langfuse_compose="$HOME/.config/langfuse/docker-compose.yml"

    _langfuse_docker_compose() {
      docker-compose --project-name langfuse -f "$_langfuse_compose" "$@"
    }

    langfuse-up() {
      colima status >/dev/null 2>&1 || colima start
      _langfuse_docker_compose up -d
      echo "Langfuse: http://localhost:3200"
    }
    langfuse-down() {
      _langfuse_docker_compose down
    }
    langfuse-status() {
      _langfuse_docker_compose ps
    }
    langfuse-logs() {
      _langfuse_docker_compose logs -f
    }
  '';
}
