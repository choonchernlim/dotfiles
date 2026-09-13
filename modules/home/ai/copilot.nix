# Copilot CLI: shared-instructions/settings symlinks, MCP config, and the
# reconcile sweep keeping its plugin store empty (nix declares none).
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
    args = [ "@playwright/mcp@latest" ];
  };
in

{
  home = {
    file = {
      ".copilot/copilot-instructions.md".source = mkOut "${aiDir}/AGENTS.md";
      ".copilot/settings.json".source = mkOut "${aiDir}/settings/copilot.json";
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
    # comment lines, clear installedPlugins (keeping trustedFolders etc.),
    # re-add the header - atomically via tmp+mv.
    activation.copilotReconcile = mkReconcile {
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

        # Stale backups: home-manager's *.hm-bak and the agent's own dated
        # settings.json.YYYYMMDD copies. Permanent sweep.
        find "$HOME/.copilot" -maxdepth 1 \
          \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
          -exec rm -rf {} + 2>/dev/null || true
      '';
    };
  };
}
