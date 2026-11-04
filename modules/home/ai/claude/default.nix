# Claude Code: shared-instructions/skills/settings symlinks, playwright MCP
# registration, and the reconcile sweep keeping ~/.claude plugin state
# nix-declared (prune what is undeclared, install what is declared). The
# temporary Langfuse tag patch lives in ./langfuse.nix.
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
    args = [ "@playwright/mcp@0.0.83" ];
  };

  # Declared plugins/marketplaces are whatever home/ai/settings/claude.json
  # enables - that file is the single place to add one. claudeReconcile below
  # prunes everything else from ~/.claude/plugins, and claudePlugins installs
  # whatever is declared but absent.
  claudeSettings = builtins.fromJSON (builtins.readFile ../../../../home/ai/settings/claude.json);
  claudeKeepInstalled = builtins.attrNames (claudeSettings.enabledPlugins or { });
  claudeKeepMarketplaces = builtins.attrNames (claudeSettings.extraKnownMarketplaces or { });

  # Each declared plugin id ("name@marketplace") paired with its marketplace's
  # git URL. A plugin whose marketplace is not declared fails at eval, instead
  # of being installed and then pruned by the next reconcile.
  claudePluginInstalls = map (
    id:
    assert lib.assertMsg (lib.hasInfix "@" id)
      "claude.json: plugin ${id} must be named name@marketplace";
    {
      inherit id;
      url =
        claudeSettings.extraKnownMarketplaces.${lib.last (lib.splitString "@" id)}.source.url
        or (throw "claude.json: plugin ${id} needs an extraKnownMarketplaces entry with a git source.url");
    }
  ) claudeKeepInstalled;

  # Shell case-branches for the marketplaces/ and cache/ dir sweep.
  claudeKeepMarketplaceCases = lib.concatMapStringsSep "\n              " (
    p: ''"${p}") continue ;;''
  ) claudeKeepMarketplaces;

  modelOverride = config.dotfiles.claude.model;
in

{
  imports = [ ./langfuse.nix ];

  options.dotfiles.claude.model = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "opus";
    description = "Per-host model passed to the `claude` alias as `--model` (see docs/gotchas.md).";
  };

  config = {
    # Tag Claude's Langfuse traces with the launch dir (see ./langfuse.nix for
    # CC_LANGFUSE_TAGS). A prefix assignment scopes it to that one process; the
    # trailing bare name hits the real binary (zsh alias-recursion guard).
    # --model is a session-only override: it never writes back to settings.json
    # and /model still switches mid-session.
    programs.zsh.shellAliases.claude =
      ''CC_LANGFUSE_TAGS="''${PWD:t}" claude''
      + lib.optionalString (modelOverride != null) " --model ${modelOverride}";

    home = {
      file = {
        ".claude/CLAUDE.md".source = mkOut "${aiDir}/AGENTS.md";
        # Claude reads personal skills from ~/.claude/skills only (no native
        # ~/.agents support), so this links at the hub (../default.nix), not at
        # the repo. force: pre-nix entries here were symlinks, which
        # home-manager's backupFileExtension cannot move aside on its own.
        ".claude/skills" = {
          source = mkOut "${config.home.homeDirectory}/.agents/skills";
          force = true;
        };
        ".claude/settings.json".source = mkOut "${aiDir}/settings/claude.json";
        # The `reviewer` subagent named by AGENTS.md's pre-commit review.
        ".claude/agents/reviewer.md".source = mkOut "${aiDir}/agents/claude/reviewer.md";
        # Vendored from `herdr integration install claude`; the SessionStart hook
        # in settings/claude.json points here. mkOut so a re-install writes back
        # into the repo as a visible diff instead of a stray host-local file.
        ".claude/hooks/herdr-agent-state.sh".source = mkOut "${aiDir}/hooks/claude/herdr-agent-state.sh";
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
            # Stale backups: home-manager's *.hm-bak and the agent's own dated
            # settings.json.YYYYMMDD copies. Both recur as long as the agent
            # fights the symlink, so this sweep is permanent.
            find "$HOME/.claude" -maxdepth 1 \
              \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
              -exec rm -rf {} + 2>/dev/null || true
          '';
        };

        # Install every declared plugin that is absent (a plugin install has no
        # nix-store path that churns, so no remove-then-add). Runs after the
        # sweep so the sweep can never race what was just installed.
        #
        # Explicit HTTPS URLs, not the owner/repo shorthand: the shorthand
        # resolves to an SSH clone, and the hermetic activation PATH has no ssh.
        # /usr/bin/git (Xcode CLT) is prepended rather than pkgs.git: the nix
        # git has no bundled CA trust and relies on http.sslcainfo, which
        # zscaler.nix pins to the Zscaler cert - failing TLS whenever traffic
        # isn't actually going through Zscaler. /usr/bin/git validates against
        # the macOS Keychain on every path.
        claudePlugins = mkReconcile {
          name = "claude-plugins";
          after = [ "claudeReconcile" ];
          text = ''
            _claude=/opt/homebrew/bin/claude
            _ip="$HOME/.claude/plugins/installed_plugins.json"
            if [ -x "$_claude" ]; then
              ${lib.concatMapStringsSep "\n" (p: ''
                if ! jq -e '.plugins[${builtins.toJSON p.id}]' "$_ip" >/dev/null 2>&1; then
                  PATH="/usr/bin:$PATH" "$_claude" plugin marketplace add ${lib.escapeShellArg p.url} 2>/dev/null || true
                  PATH="/usr/bin:$PATH" "$_claude" plugin install ${lib.escapeShellArg p.id} 2>/dev/null || true
                fi
              '') claudePluginInstalls}
            fi
          '';
        };
      };
    };
  };
}
