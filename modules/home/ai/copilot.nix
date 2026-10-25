# Copilot CLI: shared-instructions/settings/reviewer symlinks, herdr and
# secret-guard hooks, MCP config with its auto-approve alias, and the reconcile
# sweep keeping its plugin store empty (nix declares none).
#
# No skills link here: Copilot discovers ~/.agents/skills natively (the hub in
# ./default.nix); a ~/.copilot/skills link on top would list every skill twice.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";
  mkReconcile = import ../lib/reconcile.nix { inherit pkgs lib; };

  # See ./default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@0.0.83" ];
  };
in

{
  # Every playwright tool runs without a prompt, like Claude's
  # mcp__playwright__* allow rule. Copilot persists no tool approvals in a
  # settings key, so the flag rides on the alias (claude's alias mechanics);
  # the PreToolUse secret guard still runs first.
  programs.zsh.shellAliases.copilot = "copilot --allow-tool=playwright";

  home = {
    file = {
      ".copilot/copilot-instructions.md".source = mkOut "${aiDir}/AGENTS.md";
      ".copilot/settings.json".source = mkOut "${aiDir}/settings/copilot.json";
      # Vendored from `herdr integration install copilot`; the SessionStart hook
      # in settings/copilot.json points here (see the claude module for why mkOut).
      ".copilot/hooks/herdr-agent-state.sh".source = mkOut "${aiDir}/hooks/copilot/herdr-agent-state.sh";
      # The PreToolUse hook in settings/copilot.json. Copilot has no read-deny
      # rule kind, so this stands in for Claude's permissions.deny. The hook
      # skips a missing script: settings.json is live before this link exists,
      # and Copilot denies every tool call whose hook fails.
      ".copilot/hooks/deny-secret-reads.sh".source = mkOut "${aiDir}/hooks/copilot/deny-secret-reads.sh";
      # The `reviewer` subagent named by AGENTS.md's pre-commit review.
      ".copilot/agents/reviewer.agent.md".source = mkOut "${aiDir}/agents/copilot/reviewer.agent.md";
      ".copilot/mcp-config.json".text = builtins.toJSON {
        mcpServers.playwright = {
          type = "local";
          inherit (playwrightMcp) command args;
          tools = [ "*" ];
        };
      };
    };

    # Filesystem + JSON reset, not CLI calls (networked, unreliable offline).
    # config.json is JSONC (// header), which jq cannot parse: strip the
    # comment lines, clear installedPlugins and drop the snake_case
    # installed_plugins (keeping trustedFolders etc.), re-add the header -
    # atomically via _apply.
    activation.copilotReconcile = mkReconcile {
      name = "copilot-reconcile";
      text = ''
        _cop="$HOME/.copilot"
        if [ -d "$_cop" ]; then
          rm -rf "$_cop/installed-plugins"
          _cf="$_cop/config.json"
          if [ -e "$_cf" ]; then
            _clear_plugins() {
              printf '// User settings belong in settings.json.\n'
              printf '// This file is managed automatically.\n'
              grep -v '^//' "$1" | jq '.installedPlugins = [] | del(.installed_plugins)'
            }
            _apply "$_cf" _clear_plugins || true
          fi
        fi

        # Stale backups: home-manager's *.hm-bak and the agent's own dated
        # settings.json.YYYYMMDD copies. Permanent sweep.
        find "$HOME/.copilot" -maxdepth 1 \
          \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
          -exec rm -rf {} + 2>/dev/null || true
      '';
    };
  };
}
