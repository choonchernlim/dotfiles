# Colima feature module: autostarts the colima container runtime at login via
# a home-manager launchd agent. Deliberately generic - not gitea-specific, so
# any container workload (gitea, or others added later) finds colima already
# running. Selected per-host via hosts/*.nix home imports (work, work-atdj);
# those hosts' homebrew bundles (modules/darwin/homebrew/{work,work-atdj}.nix)
# declare the colima/docker/docker-compose brews this agent depends on -
# importing this module without that brew leaves the agent unable to exec.
#
# No custom reconcile here, unlike the other feature modules: home-manager's
# launchd.agents already owns the plist lifecycle (writes it to
# ~/Library/LaunchAgents/, unloads it when this module stops being imported).
# One gap that leaves: unloading does not stop an already-running colima VM
# (colima ignores the SIGTERM launchd sends - abiosoft/colima#1346), so
# removing this module leaves the VM up until a manual `colima stop` or the
# next reboot.
{ config, ... }:
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
}
