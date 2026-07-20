# Colima feature module: autostarts the colima container runtime at login via
# a home-manager launchd agent. Deliberately generic - not gitea-specific, so
# any container workload (gitea, or others added later) finds colima already
# running. Selected per-host via hosts/*.nix home imports (work, personal,
# work-atdj - all 3 hosts). The colima/docker/docker-compose brews this agent
# depends on live in modules/darwin/homebrew/common.nix (the all-hosts
# intersection) - importing this module without that brew leaves the agent
# unable to exec.
#
# No custom reconcile for the launchd agent itself: home-manager's
# launchd.agents already owns the plist lifecycle (writes it to
# ~/Library/LaunchAgents/, unloads it when this module stops being imported).
# One gap that leaves: unloading does not stop an already-running colima VM
# (colima ignores the SIGTERM launchd sends - abiosoft/colima#1346), so
# removing this module leaves the VM up until a manual `colima stop` or the
# next reboot.
{ config, lib, ... }:
{
  launchd.agents.colima = {
    enable = true;
    config = {
      ProgramArguments = [
        "/opt/homebrew/bin/colima"
        "start"
      ];
      RunAtLoad = true;
      KeepAlive = false; # one-shot launcher; colima daemonizes its own VM after start
      EnvironmentVariables = {
        # launchd agents don't inherit the shell's PATH. colima shells out to
        # limactl and its VM backend, both under /opt/homebrew - omitting this
        # is the #1 cause of "colima start works in a terminal but fails under
        # launchd" (abiosoft/colima#490).
        PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = config.home.homeDirectory;
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/colima.launchd.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/colima.launchd.err.log";
    };
  };

  # Trust the Zscaler MITM root CA inside the colima guest VM. Zscaler intercepts all
  # outbound TLS on this network (same CA already used for brew's CURL_CA_BUNDLE - see
  # reference_zscaler_brew_cert memory) - without this, any `docker pull`/`docker-compose
  # up` against a registry fails with "x509: certificate signed by unknown authority"
  # (confirmed against cgr.dev while debugging langfuse's docker-compose). The VM's guest
  # OS trust store is separate from the host's, so brew's host-side CURL_CA_BUNDLE fix
  # does not cover it.
  #
  # ~/.ca_certs/zscalercert.pem itself is user/work-owned runtime state, not nix-managed
  # (same class as ~/.zshrc_conf/zscaler.sh) - this step no-ops entirely on hosts/machines
  # without that file (e.g. off this network), so it is safe to leave in all 3 hosts'
  # colima.nix import rather than gating it per-host.
  #
  # Hash-guarded so it is a no-op on every rebuild except when the cert actually changes:
  # applying it requires `sudo systemctl restart docker` inside the VM, because dockerd
  # caches the trust store at process start - `update-ca-certificates` alone is not enough
  # (confirmed: curl trusted the new cert immediately, `docker pull` still failed until the
  # daemon was restarted). That restart briefly restarts already-running containers
  # (confirmed against gitea/gitea-db - both came back healthy under their `restart:
  # unless-stopped` policy), so it must not fire on every rebuild, only on real cert
  # rotation. Best-effort on VM readiness: if colima isn't up yet when this activation
  # runs, it no-ops and self-heals on the next rebuild once colima has started - same
  # accepted timing gap as the SIGTERM caveat above.
  home.activation.colimaZscalerCert = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _zscaler_cert="${config.home.homeDirectory}/.ca_certs/zscalercert.pem"
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
}
