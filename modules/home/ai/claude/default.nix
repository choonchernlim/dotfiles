# Claude Code: shared-instructions/skills/settings symlinks, playwright MCP
# registration, and the reconcile sweep keeping ~/.claude plugin state
# nix-declared. The Langfuse plugin (temporary) lives in ./langfuse.nix.
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
  mkReconcile = import ../../lib/reconcile.nix { inherit pkgs lib; };

  # See ../default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };

  # Declared plugins/marketplaces are whatever home/ai/settings/claude.json
  # enables - that file is the single place to add one. The reconcile below
  # prunes everything else from ~/.claude/plugins. (enabledPlugins does not
  # install; ./langfuse.nix does that for the one plugin currently declared.)
  claudeSettings = builtins.fromJSON (builtins.readFile ../../../../home/ai/settings/claude.json);
  claudeKeepInstalled = builtins.attrNames (claudeSettings.enabledPlugins or { });
  claudeKeepMarketplaces = builtins.attrNames (claudeSettings.extraKnownMarketplaces or { });

  # Shell case-branches for the marketplaces/ and cache/ dir sweep.
  claudeKeepMarketplaceCases = lib.concatMapStringsSep "\n              " (
    p: ''"${p}") continue ;;''
  ) claudeKeepMarketplaces;
in

{
  imports = [ ./langfuse.nix ];

  # Tag Claude's Langfuse traces with the launch dir (see ./langfuse.nix for
  # CC_LANGFUSE_TAGS). A prefix assignment scopes it to that one process; the
  # trailing bare name hits the real binary (zsh alias-recursion guard).
  programs.zsh.shellAliases.claude = ''CC_LANGFUSE_TAGS="''${PWD:t}" claude'';

  home = {
    file = {
      ".claude/CLAUDE.md".source = mkOut "${aiDir}/AGENTS.md";
      # force: pre-nix entries here were symlinks, which home-manager's
      # backupFileExtension cannot move aside on its own.
      ".claude/skills" = {
        source = mkOut "${aiDir}/skills";
        force = true;
      };
      ".claude/settings.json".source = mkOut "${aiDir}/settings/claude.json";
    };

    activation = {
      # Register playwright MCP (lives in ~/.claude.json, not symlinkable).
      # Remove-then-add every rebuild: the command is a nix-store path that
      # changes with nodejs updates, so add-if-absent would leave a stale
      # command registered forever. No-op if claude is not installed.
      claudePlaywrightMcp = mkReconcile {
        name = "claude-playwright-mcp";
        text = ''
          _claude=/opt/homebrew/bin/claude
          if [ -x "$_claude" ]; then
            "$_claude" mcp remove --scope user playwright 2>/dev/null || true
            "$_claude" mcp add --scope user playwright -- ${playwrightMcp.command} ${lib.concatStringsSep " " playwrightMcp.args} || true
          fi
        '';
      };

      # Keep-set prune of plugin state (installed_plugins.json,
      # known_marketplaces.json, marketplaces/ and cache/ dirs): everything not
      # declared in settings/claude.json is removed. JSON is rewritten via
      # json_edit (atomic); the MCP registry is only ever mutated through the CLI.
      claudeReconcile = mkReconcile {
        name = "claude-reconcile";
        after = [ "claudePlaywrightMcp" ];
        text = ''
          _claude_plugins="$HOME/.claude/plugins"
          if [ -d "$_claude_plugins" ]; then
            _ip="$_claude_plugins/installed_plugins.json"
            if [ -e "$_ip" ]; then
              json_edit "$_ip" --argjson keep '${builtins.toJSON claudeKeepInstalled}' \
                '.version = (.version // 2) | .plugins = ((.plugins // {}) | with_entries(select(.key as $k | $keep | index($k))))'
            else
              printf '{"version":2,"plugins":{}}' > "$_ip"
            fi
            _km="$_claude_plugins/known_marketplaces.json"
            if [ -e "$_km" ]; then
              json_edit "$_km" --argjson keep '${builtins.toJSON claudeKeepMarketplaces}' \
                'with_entries(select(.key as $k | $keep | index($k)))'
            else
              printf '{}' > "$_km"
            fi
            for _base in marketplaces cache; do
              _dir="$_claude_plugins/$_base"
              [ -d "$_dir" ] || continue
              for _entry in "$_dir"/*; do
                [ -e "$_entry" ] || continue
                _name=$(basename "$_entry")
                case "$_name" in
                  ${claudeKeepMarketplaceCases}
                  *) rm -rf "$_entry" ;;
                esac
              done
            done
          fi
          _claude=/opt/homebrew/bin/claude
          if [ -x "$_claude" ]; then
            "$_claude" mcp remove --scope user context7 2>/dev/null || true
          fi

          # Stale backups: home-manager's *.hm-bak and the agent's own dated
          # settings.json.YYYYMMDD copies. Both recur as long as the agent
          # fights the symlink, so this sweep is permanent.
          find "$HOME/.claude" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
