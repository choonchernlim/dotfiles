# Copilot CLI: shared-instructions/skills/settings symlinks, MCP config, and the
# reconcile sweep keeping its plugin store empty (nix declares no copilot plugins).
# Deliberately self-contained - see ./default.nix for the per-agent-file convention.
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

  # The playwright MCP server Copilot gets. Deliberately duplicated in every
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
  home = {
    file = {
      # Shared instructions -> Copilot's canonical filename.
      ".copilot/copilot-instructions.md".source = mkOut "${aiDir}/AGENTS.md";

      # Shared skills dir -> Copilot's skills dir.
      # force = true: existing entries are symlinks (from Ansible), not regular files,
      # so home-manager's backupFileExtension cannot move them aside automatically.
      ".copilot/skills" = {
        source = mkOut "${aiDir}/skills";
        force = true;
      };

      ".copilot/settings.json".source = mkOut "${aiDir}/settings/copilot.json";

      # Copilot MCP: JSON, mcpServers.<name>
      ".copilot/mcp-config.json".text = builtins.toJSON {
        mcpServers.playwright = {
          type = "local";
          inherit (playwrightMcp) command args;
          tools = [ "*" ];
        };
      };
    };

    activation = {
      # Enforce nix as the single source of truth for Copilot plugins: nix declares
      # none, so the installed-plugins dir is removed entirely and installedPlugins
      # cleared in config.json on every rebuild. Filesystem + JSON reset, not CLI
      # calls - the CLI is networked/unreliable offline.
      # config.json is JSONC (// comment header), which jq cannot parse directly:
      # strip comment lines, clear installedPlugins (preserving trustedFolders,
      # expAssignmentsCache, ...), re-add the header - atomically via tmp+mv.
      # Safety: every rm is on an explicit quoted path; [ -e ]/[ -d ] guards skip
      # missing files.
      copilotReconcile = mkReconcile {
        name = "copilot-reconcile";
        text = ''
          _cop="$HOME/.copilot"
          if [ -d "$_cop" ]; then
            rm -rf "$_cop/installed-plugins"
            _cf="$_cop/config.json"
            if [ -e "$_cf" ]; then
              _tmp=$(mktemp "$_cf.XXXXXX")
              if {
                printf '// User settings belong in settings.json.\n'
                printf '// This file is managed automatically.\n'
                grep -v '^//' "$_cf" | jq '.installedPlugins = []'
              } > "$_tmp" 2>/dev/null; then
                mv "$_tmp" "$_cf"
              else
                rm -f "$_tmp"
              fi
            fi
          fi

          # Stale backups (.hm-bak and agent-created dated copies):
          # home-manager creates *.hm-bak when replacing a file that already existed;
          # agents create settings.json.YYYYMMDD before overwriting their config.
          # Both recur as long as agents fight the symlinks, so this sweep is
          # permanent (unlike the one-shot first-takeover .hm-baks in legacy.nix).
          # Each agent module sweeps its own config dir.
          find "$HOME/.copilot" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
