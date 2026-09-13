# Docker feature module: reconciles the credential settings in ~/.docker/config.json.
# Selected per-host via hosts/*.nix home imports (all 3 hosts, like colima.nix).
#
# A reconcile, not a home.file symlink: `docker login` and `gcloud auth
# configure-docker` both write into this same file at runtime, so this module
# owns only the two keys below and merges around everything else.
#
#   - credsStore = "osxkeychain": registry passwords go to the macOS Keychain,
#     not base64 plaintext in this file. The helper binary comes from the
#     docker-credential-helper brew in homebrew/common.nix.
#   - credHelpers["us-central1-docker.pkg.dev"] = "gcloud": that registry uses
#     gcloud's short-lived tokens instead. Merged in, so other GCP entries
#     `gcloud auth configure-docker` adds survive.
{ pkgs, lib, ... }:

let
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in

{
  home.activation.dockerCredsSetup = mkReconcile {
    name = "docker-creds-setup";
    text = ''
      _docker_config="$HOME/.docker/config.json"
      mkdir -p "$HOME/.docker"
      [ -e "$_docker_config" ] || printf '{}' > "$_docker_config"

      json_edit "$_docker_config" \
        '.credsStore = "osxkeychain"
         | .credHelpers = ((.credHelpers // {}) + {"us-central1-docker.pkg.dev": "gcloud"})'
    '';
  };
}
