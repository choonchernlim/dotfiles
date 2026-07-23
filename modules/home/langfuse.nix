# Langfuse feature module: local observability stack via Docker Compose,
# started manually with langfuse-up/langfuse-down/langfuse-status/langfuse-logs.
# Selected only by the work host. Colima's generic login agent starts the
# container runtime, and the compose services' `restart: always` policies bring
# previously created containers back after login. A fresh host needs one
# explicit `langfuse-up`.
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
    # Link only the compose file so the directory remains available for a
    # future user-owned .env without ever committing secrets to this public repo.
    file.".config/langfuse/docker-compose.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/langfuse/docker-compose.yml";

    activation.langfuseReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "$HOME/.config/langfuse/docker-compose.yml.hm-bak" || true
      [ -d "$HOME/.config/langfuse.hm-bak" ] && rm -rf "$HOME/.config/langfuse.hm-bak" || true
    '';
  };

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
