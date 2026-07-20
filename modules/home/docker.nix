# Docker feature module: reconciles ~/.docker/config.json's credential settings.
# Selected per-host via hosts/*.nix home imports (work, personal, work-atdj - all 3
# hosts, same as colima.nix, since all 3 get docker via homebrew/common.nix).
#
# Why a reconcile and not a home.file symlink: docker (`docker login`) and gcloud
# (`gcloud auth configure-docker`) both write into this same file at runtime (auths,
# extra credHelpers entries). A read-only nix-store symlink here would break those
# writes, so this module owns only the two keys it cares about and merges around
# everything else, mirroring gcloudSetup in modules/home/gcloud.nix.
#
# What it enforces:
#   - credsStore = "osxkeychain": every registry not otherwise overridden gets its
#     password stored encrypted in the macOS Keychain, rather than base64 plaintext
#     in this file - secure-by-default as more private registries are added over
#     time. The helper binary (docker-credential-osxkeychain) comes from the
#     docker-credential-helper brew in homebrew/common.nix; it is a standalone
#     MIT-licensed helper (docker/docker-credential-helpers), not a Docker Desktop
#     dependency, so it works fine on a colima-only box.
#   - credHelpers["us-central1-docker.pkg.dev"] = "gcloud": the one registry that
#     should keep using gcloud's short-lived OAuth tokens (docker-credential-gcloud,
#     from the gcloud-cli cask) instead of a stored password. Merged in, not
#     overwritten - `gcloud auth configure-docker` legitimately adds other GCP
#     registry entries (gcr.io, us-docker.pkg.dev, ...) here and those must survive.
{ lib, ... }:

{
  home.activation.dockerCredsSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _docker_dir="$HOME/.docker"
    _docker_config="$_docker_dir/config.json"
    mkdir -p "$_docker_dir"
    [ -e "$_docker_config" ] || printf '{}' > "$_docker_config"

    if command -v jq >/dev/null 2>&1; then
      _updated=$(jq \
        '.credsStore = "osxkeychain"
         | .credHelpers = ((.credHelpers // {}) + {"us-central1-docker.pkg.dev": "gcloud"})' \
        "$_docker_config" 2>/dev/null) || true
      if [ -n "$_updated" ]; then
        printf '%s\n' "$_updated" > "$_docker_config"
      fi
    fi
  '';
}
