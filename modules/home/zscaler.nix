# Zscaler feature module: wiring for the corporate Zscaler MITM proxy that intercepts all
# outbound TLS on the work network. Selected per-host via hosts/*.nix home imports (work,
# work-atdj only - same {work, work-atdj} selection as gitea.nix; personal is not behind
# Zscaler).
#
# The cert file itself (~/.ca_certs/zscalercert.pem) is deliberately NOT nix-managed and
# stays user/work-owned runtime state: it's a corporate root CA, this repo is a public fork,
# and nix cannot provision it first anyway - bootstrap.sh's own curl and the Nix installer
# need OS-level TLS trust before nix ever runs, which comes from the Zscaler client/MDM
# installing the cert into the system keychain out-of-band. Every step below only *consumes*
# the cert by reference and no-ops cleanly when it's absent.
#
# Supersedes the old user-owned ~/.zshrc_conf/zscaler.sh, which set the same two active
# variables below (NODE_EXTRA_CA_CERTS, git http.sslcainfo - its other lines, SSL_CERT_FILE/
# CURL_CA_BUNDLE/wget/pip/gcloud, were already commented out and are not migrated - the
# on-demand brew CURL_CA_BUNDLE/SSL_CERT_FILE workflow documented in the
# reference_zscaler_brew_cert memory is unaffected). zscalerReconcile below removes that file
# so it can't drift back out of sync with this module.
{ config, lib, ... }:
let
  certPath = "${config.home.homeDirectory}/.ca_certs/zscalercert.pem";
in
{
  home = {
    # NPM/Node: matches the old zscaler.sh export. Unconditional (cheap to declare; Node only
    # warns, non-fatally, if the path doesn't exist), consistent with ai.nix's sessionVariables.
    sessionVariables.NODE_EXTRA_CA_CERTS = certPath;

    activation = {
      # git: matches the old zscaler.sh `git config --global http.sslcainfo`. Writes into the
      # user-owned ~/.gitconfig via the git CLI rather than adopting programs.git wholesale -
      # same non-invasive approach gcloudSetup uses for gcloud's own config (modules/home/gcloud.nix).
      # Guarded on the cert existing: an absent cert must not overwrite a previously-good
      # sslcainfo with a path that would then break every https git operation.
      # Absolute path, not `command -v` - home-manager's activation PATH is hermetic (bash/
      # coreutils/grep/sed/jq from the nix store only, no /usr/bin), so a PATH-based lookup here
      # would silently no-op. /usr/bin/git is the Xcode CLT git; this machine has no brew git.
      zscalerGitCert = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _zscaler_cert="${certPath}"
        _git=/usr/bin/git
        if [ -f "$_zscaler_cert" ] && [ -x "$_git" ]; then
          "$_git" config --global http.sslcainfo "$_zscaler_cert" || true
        fi
      '';

      # Trust the Zscaler MITM root CA inside the colima guest VM. Without this, any
      # `docker pull`/`docker-compose up` against a registry fails with "x509: certificate
      # signed by unknown authority" (confirmed against cgr.dev while debugging langfuse's
      # docker-compose). The VM's guest OS trust store is separate from the host's, so the
      # NODE_EXTRA_CA_CERTS/git fixes above (host-side) do not cover it.
      #
      # Hash-guarded so it is a no-op on every rebuild except when the cert actually changes:
      # applying it requires `sudo systemctl restart docker` inside the VM, because dockerd
      # caches the trust store at process start - `update-ca-certificates` alone is not enough
      # (confirmed: curl trusted the new cert immediately, `docker pull` still failed until the
      # daemon was restarted). That restart briefly restarts already-running containers
      # (confirmed against gitea/gitea-db - both came back healthy under their `restart:
      # unless-stopped` policy), so it must not fire on every rebuild, only on real cert
      # rotation. Best-effort on VM readiness: if colima isn't up yet when this activation runs,
      # it no-ops and self-heals on the next rebuild once colima has started - same accepted
      # timing gap as colima.nix's own SIGTERM caveat.
      colimaZscalerCert = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _zscaler_cert="${certPath}"
        _colima=/opt/homebrew/bin/colima
        if [ -f "$_zscaler_cert" ] && [ -x "$_colima" ] && "$_colima" status >/dev/null 2>&1; then
          _local_sum=$(sha256sum "$_zscaler_cert" | awk '{print $1}') || true
          _remote_sum=$("$_colima" ssh -- sha256sum /usr/local/share/ca-certificates/zscaler.crt 2>/dev/null | awk '{print $1}') || true
          if [ -n "$_local_sum" ] && [ "$_local_sum" != "$_remote_sum" ]; then
            "$_colima" ssh -- sudo cp "$_zscaler_cert" /usr/local/share/ca-certificates/zscaler.crt 2>/dev/null || true
            "$_colima" ssh -- sudo update-ca-certificates 2>/dev/null || true
            "$_colima" ssh -- sudo systemctl restart docker 2>/dev/null || true
          fi
        fi
      '';

      # Superseded by this module (NODE_EXTRA_CA_CERTS + git sslcainfo above) - removed so it
      # can't drift out of sync or double-set the same config. Same pattern as aiReconcile
      # removing the old ~/.zshrc_conf/ai.sh in modules/home/ai.nix.
      zscalerReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        rm -f "$HOME/.zshrc_conf/zscaler.sh" || true
      '';
    };
  };
}
