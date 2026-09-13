# Zscaler feature module: trust the corporate Zscaler MITM root CA wherever TLS
# is verified outside the macOS Keychain. Selected per-host via hosts/*.nix
# (work, work-atdj; personal is not behind Zscaler).
#
# The cert file (~/.ca_certs/zscalercert.pem) is deliberately NOT nix-managed:
# it is a corporate root CA in a public repo, and OS-level trust must already
# exist (via the Zscaler client/MDM) before bootstrap.sh can even fetch nix.
# Every step below only consumes the cert by reference and no-ops when absent.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  certPath = "${config.home.homeDirectory}/.ca_certs/zscalercert.pem";
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in
{
  home = {
    # Node: unconditional; node only warns, non-fatally, if the path is missing.
    sessionVariables.NODE_EXTRA_CA_CERTS = certPath;

    activation = {
      # git: written into the user-owned ~/.gitconfig via the git CLI rather
      # than adopting programs.git wholesale. Guarded on the cert existing so an
      # absent cert never replaces a good sslcainfo with a dead path. /usr/bin/git
      # (Xcode CLT) by absolute path: the activation PATH is hermetic.
      zscalerGitCert = mkReconcile {
        name = "zscaler-git-cert";
        text = ''
          _zscaler_cert="${certPath}"
          _git=/usr/bin/git
          if [ -f "$_zscaler_cert" ] && [ -x "$_git" ]; then
            "$_git" config --global http.sslcainfo "$_zscaler_cert" || true
          fi
        '';
      };

      # Trust the CA inside the colima guest VM, whose trust store is separate
      # from the host's; without it `docker pull` fails with "x509: certificate
      # signed by unknown authority".
      #
      # Hash-guarded: applying requires restarting dockerd in the VM (it caches
      # the trust store at start), which briefly restarts running containers,
      # so it only fires on real cert rotation. If colima is not up yet, this
      # no-ops and self-heals on the next rebuild. /opt/homebrew/bin is
      # prepended because colima shells out to limactl there.
      colimaZscalerCert = mkReconcile {
        name = "colima-zscaler-cert";
        text = ''
          export PATH="/opt/homebrew/bin:$PATH"
          _zscaler_cert="${certPath}"
          _colima=/opt/homebrew/bin/colima
          if [ -f "$_zscaler_cert" ] && [ -x "$_colima" ] && "$_colima" status >/dev/null 2>&1; then
            _local_sum=$(sha256sum "$_zscaler_cert" | cut -d' ' -f1) || _local_sum=""
            _remote_sum=$("$_colima" ssh -- sha256sum /usr/local/share/ca-certificates/zscaler.crt 2>/dev/null | cut -d' ' -f1) || _remote_sum=""
            if [ -n "$_local_sum" ] && [ "$_local_sum" != "$_remote_sum" ]; then
              "$_colima" ssh -- sudo cp "$_zscaler_cert" /usr/local/share/ca-certificates/zscaler.crt 2>/dev/null || true
              "$_colima" ssh -- sudo update-ca-certificates 2>/dev/null || true
              "$_colima" ssh -- sudo systemctl restart docker 2>/dev/null || true
            fi
          fi
        '';
      };
    };
  };
}
