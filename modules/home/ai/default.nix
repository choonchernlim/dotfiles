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
# Skills hub - the ONE agent-agnostic declaration in this directory:
#   ~/.agents/skills -> home/ai/skills (live, out-of-store). Codex, Copilot and
#   OpenCode discover ~/.agents/skills natively and therefore declare no skills
#   link of their own: a second link would surface every skill twice (Codex
#   documents that same-named skills are not merged). Claude and Antigravity do
#   not read ~/.agents, so each links its own skills dir at the hub - never at
#   the repo path directly, so the hub stays the single place to look.
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
{ config, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";
in

{
  imports = [
    ./claude
    ./codex
    ./antigravity.nix
    ./copilot.nix
    ./opencode.nix
  ];

  # force: a pre-existing ~/.agents/skills (hand-made symlink, or one written by
  # a skills installer CLI) is replaced, not backed up - home-manager's
  # backupFileExtension cannot move a symlink aside on its own.
  home.file.".agents/skills" = {
    source = mkOut "${aiDir}/skills";
    force = true;
  };
}
