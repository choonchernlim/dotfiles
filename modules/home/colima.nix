# Colima feature module: autostarts the container runtime at login via a
# home-manager launchd agent, so any container workload (gitea, langfuse, ...)
# finds it running, and prunes it weekly (all unused images monthly) so the
# sparse VM disk stays small.
# Selected per-host via hosts/*.nix (all 3 hosts). The colima/docker/
# docker-compose brews it needs live in homebrew/common.nix.
#
# No reconcile: home-manager owns the plist lifecycle (writes it, unloads it
# when the module is dropped). Known gap: unloading does not stop a running VM
# (colima ignores launchd's SIGTERM, abiosoft/colima#1346) - `colima stop` by hand.
{
  config,
  pkgs,
  ...
}:

let
  # Prune, then fstrim: pruning frees blocks inside the VM, but the sparse disk
  # image only shrinks on the Mac once the guest trims them (its own
  # fstrim.timer is weekly and unrelated to the prune). Volumes are never
  # pruned (gitea and langfuse data live there). Tagged unused images are only
  # removed by the monthly run (--all-images), because re-pulling them goes
  # through the Zscaler proxy.
  colimaPrune = pkgs.writeShellApplication {
    name = "colima-prune";
    text = ''
      # VM down or daemon not ready yet (e.g. a missed job firing right at
      # wake): nothing to prune, and fstrim needs the guest. Retry next run.
      if ! colima status >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "colima-prune: skipped (colima or docker not ready)"
        exit 0
      fi
      # A failed prune must not skip the trim; report it via the exit status.
      rc=0
      docker builder prune --force --filter until=168h || rc=1
      docker image prune --force --filter until=168h || rc=1
      docker container prune --force --filter until=168h || rc=1
      if [ "''${1:-}" = "--all-images" ]; then
        docker image prune --all --force --filter until=720h || rc=1
      fi
      colima ssh -- sudo fstrim -av || rc=1
      exit "$rc"
    '';
  };

  # launchd runs a calendar job missed during sleep once the Mac wakes.
  mkPruneAgent = name: args: schedule: {
    enable = true;
    config = {
      ProgramArguments = [ "${colimaPrune}/bin/colima-prune" ] ++ args;
      StartCalendarInterval = [ schedule ];
      EnvironmentVariables = {
        # Same brew PATH and HOME as the autostart agent: colima and docker are
        # Homebrew-managed, and docker finds the colima context under $HOME.
        PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = config.home.homeDirectory;
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.err.log";
    };
  };
in
{
  launchd.agents = {
    colima = {
      enable = true;
      config = {
        ProgramArguments = [
          "/opt/homebrew/bin/colima"
          "start"
          # 8GiB, up from the 2GiB default - langfuse's ClickHouse needs the
          # headroom. Only applies on first VM creation or after `colima stop`;
          # `colima start` ignores flags when the VM is already running.
          "--memory"
          "8"
        ];
        RunAtLoad = true;
        KeepAlive = false; # one-shot launcher; colima daemonizes its own VM
        EnvironmentVariables = {
          # launchd agents don't inherit the shell's PATH; colima shells out to
          # limactl under /opt/homebrew (abiosoft/colima#490).
          PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = config.home.homeDirectory;
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/colima.launchd.out.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/colima.launchd.err.log";
      };
    };

    colima-prune = mkPruneAgent "colima.prune" [ ] {
      Weekday = 0; # Sunday
      Hour = 3;
      Minute = 0;
    };
    colima-prune-monthly = mkPruneAgent "colima.prune-monthly" [ "--all-images" ] {
      Day = 1;
      Hour = 4;
      Minute = 0;
    };
  };
}
