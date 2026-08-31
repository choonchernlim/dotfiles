# All AI-agent configuration, split one file per agent. Each agent file is
# deliberately self-contained: its symlinks, MCP registration, plugins, env
# vars, and reconcile sweeps live together, even where that duplicates a few
# definitions across files - notably playwrightMcp (change it in every ai/*.nix
# that declares it, not just one). Shared *sources* stay deduplicated in
# home/ai/ (AGENTS.md, skills/, settings/); only their per-agent declarations
# are repeated here. Hosts import this directory as one umbrella module
# (../modules/home/ai); all hosts get all agents.
#
# The single-source-of-truth invariant (nix owns all agent plugins/extensions/
# MCP; undeclared installs are reverted on the next rebuild) is enforced by the
# per-agent reconcile activations: claudeReconcile (claude.nix),
# antigravityReconcile (antigravity.nix - also sweeps ~/.gemini/extensions,
# the root import source antigravity reimports plugins from), copilotReconcile
# (copilot.nix), and codexReconcile (codex.nix, stale-backup sweep only).
{
  imports = [
    ./claude.nix
    ./codex.nix
    ./antigravity.nix
    ./copilot.nix
    ./opencode.nix
  ];
}
