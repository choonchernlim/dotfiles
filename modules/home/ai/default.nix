# All AI-agent configuration, one self-contained unit per agent: its symlinks,
# MCP registration, plugins, env vars, and reconcile sweeps live together, even
# where that duplicates a definition across agents. Shared *sources* stay
# deduplicated in home/ai/ (AGENTS.md, skills/, settings/); only their
# per-agent declarations repeat. Hosts import this directory; all hosts get
# all agents.
#
# The invariant every agent's reconcile enforces: nix owns all agent plugins,
# extensions, and MCP servers. Anything installed out-of-band is removed on the
# next rebuild; to keep something, declare it here.
#
# playwrightMcp (duplicated per agent, on purpose - change every copy):
#   command is an absolute nix-store npx, not bare "npx". node comes only from
#   mise's interactive-shell hook, which agents' MCP child processes don't
#   inherit, so a PATH-based lookup fails there (codex: "No such file or
#   directory" exec'ing "npx"). ${pkgs.nodejs}/bin/npx resolves everywhere,
#   including work-atdj (no mise), without putting node on the interactive
#   PATH: pkgs.nodejs is referenced only here, never added to home.packages.
#
# Agent CLIs are called by absolute /opt/homebrew/bin path, never `command -v`:
# home-manager's activation PATH is hermetic (nix-store bash/coreutils/grep/
# sed/jq only) and a PATH lookup silently no-ops.
{
  imports = [
    ./claude
    ./codex
    ./antigravity.nix
    ./copilot.nix
    ./opencode.nix
  ];
}
