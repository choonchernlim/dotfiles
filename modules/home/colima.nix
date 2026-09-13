# Colima feature module: autostarts the container runtime at login via a
# home-manager launchd agent, so any container workload (gitea, langfuse, ...)
# finds it running. Selected per-host via hosts/*.nix (all 3 hosts). The
# colima/docker/docker-compose brews it needs live in homebrew/common.nix.
#
# No reconcile: home-manager owns the plist lifecycle (writes it, unloads it
# when the module is dropped). Known gap: unloading does not stop a running VM
# (colima ignores launchd's SIGTERM, abiosoft/colima#1346) - `colima stop` by hand.
{ config, ... }:
{
  launchd.agents.colima = {
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
}
