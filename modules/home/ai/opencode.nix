# OpenCode: shared-instructions/skills symlinks and opencode.json (MCP).
# No plugin store or runtime-rewritten config, so nothing to reconcile.
# Deliberately self-contained - see ./default.nix for the per-agent-file convention.
{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";

  # The playwright MCP server OpenCode gets. Deliberately duplicated in every
  # ai/*.nix (self-contained agent files - see ./default.nix); when changing
  # command/args, update the copy in each agent file.
  # command is an absolute nix-store path, not bare "npx": node/npx on this machine come only
  # from mise, which puts them on PATH via its interactive-shell hook. Agents spawn MCP child
  # processes with a reduced environment that doesn't carry that hook (confirmed: codex fails
  # with "No such file or directory (os error 2)" trying to exec bare "npx"), so a PATH-based
  # lookup silently fails there. ${pkgs.nodejs}/bin/npx resolves regardless of PATH, on every
  # host (including work-atdj, which has no mise), without adding node to the interactive PATH
  # (pkgs.nodejs is referenced here only, never added to home.packages, so it can't collide
  # with mise's own node).
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };
in

{
  home.file = {
    # Shared instructions -> OpenCode's canonical filename.
    ".config/opencode/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";

    # Shared skills dir -> OpenCode's skills dir.
    # force = true: existing entries are symlinks (from Ansible), not regular files,
    # so home-manager's backupFileExtension cannot move them aside automatically.
    ".config/opencode/skills" = {
      source = mkOut "${aiDir}/skills";
      force = true;
    };

    # OpenCode: MCP servers live under the top-level "mcp" key, "command" as a single array.
    ".config/opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      mcp.playwright = {
        type = "local";
        command = [ playwrightMcp.command ] ++ playwrightMcp.args;
        enabled = true;
      };
    };
  };
}
