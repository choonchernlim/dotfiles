{
  config,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";

  # Nix-declared antigravity plugin names (basenames under ~/.gemini/antigravity-cli/plugins/).
  # The aiReconcile sweep removes every other entry.
  # To add a plugin: declare its source in home.file above AND add its name here.
  antigravityKeepPlugins = [ "playwright" ];

  # Shell case-branches generated from the keep-set used by the reconcile sweep.
  # Each branch matches a plugin basename and skips it (continue).
  antigravityKeepCases = lib.concatMapStringsSep "\n        " (
    p: ''"${p}") continue ;;''
  ) antigravityKeepPlugins;
in

{
  home = {
    # Shared instructions -> each agent's canonical filename
    file = lib.mkMerge [
      (lib.genAttrs
        [
          ".claude/CLAUDE.md"
          ".codex/AGENTS.md"
          ".config/opencode/AGENTS.md"
          ".gemini/antigravity-cli/ANTIGRAVITY.md"
          ".copilot/copilot-instructions.md"
        ]
        (_: {
          source = mkOut "${aiDir}/AGENTS.md";
        })
      )

      # Shared skills dir -> each agent's skills dir
      # force = true: existing entries are symlinks (from Ansible), not regular files,
      # so home-manager's backupFileExtension cannot move them aside automatically.
      (lib.genAttrs
        [
          ".claude/skills"
          ".codex/skills"
          ".config/opencode/skills"
          ".gemini/antigravity-cli/skills"
          ".copilot/skills"
        ]
        (_: {
          source = mkOut "${aiDir}/skills";
          force = true;
        })
      )

      # Per-agent settings and MCP configs
      {
        ".claude/settings.json".source = mkOut "${aiDir}/settings/claude.json";
        ".gemini/antigravity-cli/settings.json".source = mkOut "${aiDir}/settings/antigravity.json";
        ".copilot/settings.json".source = mkOut "${aiDir}/settings/copilot.json";
        ".copilot/mcp-config.json".source = mkOut "${aiDir}/mcp/copilot/mcp-config.json";
        ".codex/config.toml".source = mkOut "${aiDir}/mcp/codex/config.toml";
        ".gemini/antigravity-cli/plugins/playwright".source = mkOut "${aiDir}/mcp/antigravity/playwright";
        # rtk hook integrations (declarative - rtk init never runs on this system)
        ".copilot/hooks/rtk-rewrite.json".source = mkOut "${aiDir}/hooks/copilot/rtk-rewrite.json";
        ".config/opencode/plugins/rtk.ts".source = mkOut "${aiDir}/hooks/opencode/rtk.ts";
      }
    ];

    sessionVariables = {
      ANTHROPIC_MODEL = "opusplan";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-8";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-6";
    };

    # Register playwright MCP for Claude (stored in ~/.claude.json, not symlinkable).
    # Guard: no-op if already registered or if claude is not on PATH during activation.
    activation.claudePlaywrightMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v claude >/dev/null 2>&1; then
        if ! claude mcp list 2>/dev/null | grep -q '^playwright'; then
          claude mcp add --scope user playwright -- npx @playwright/mcp@latest || true
        fi
      fi
    '';

    # Enforce nix as the single source of truth for all AI-agent plugins, extensions, and MCP.
    # Runs on every rebuild after claudePlaywrightMcp (so playwright is registered first).
    # Anything not declared in this file is removed. Adding a capability must be done in nix;
    # an out-of-band install via an agent CLI will be reverted on the next rebuild.
    #
    # Mechanism (hybrid):
    #   - Claude plugins: filesystem reset (installed_plugins.json + cache dirs).
    #     MCP registry in ~/.claude.json must go through the CLI (claude mcp remove).
    #   - Gemini extensions, antigravity, copilot: filesystem + JSON reset.
    #     Their CLIs are networked or disagree with on-disk state (unreliable offline).
    #
    # Safety: every rm is on an explicit quoted path; [ -e ] or find guards prevent abort
    # on missing files; || true keeps a transient failure from killing the whole rebuild.
    activation.aiReconcile = lib.hm.dag.entryAfter [ "writeBoundary" "claudePlaywrightMcp" ] ''
      # ── Claude: plugin store + undeclared MCP ──────────────────────────────
      # Plugin JSON state files live under ~/.claude/plugins/ which we own directly.
      # ~/.claude.json (MCP registry) must be mutated via the claude CLI, not by hand.
      _claude_plugins="$HOME/.claude/plugins"
      if [ -d "$_claude_plugins" ]; then
        printf '{"version":2,"plugins":{}}' > "$_claude_plugins/installed_plugins.json" || true
        printf '{}' > "$_claude_plugins/known_marketplaces.json" || true
        [ -d "$_claude_plugins/cache/claude-plugins-official" ] && \
          rm -rf "$_claude_plugins/cache/claude-plugins-official" || true
        [ -d "$_claude_plugins/marketplaces/claude-plugins-official" ] && \
          rm -rf "$_claude_plugins/marketplaces/claude-plugins-official" || true
      fi
      if command -v claude >/dev/null 2>&1; then
        claude mcp remove --scope user context7 2>/dev/null || true
      fi

      # ── Gemini CLI extensions (root import source for antigravity) ──────────
      # nix declares no gemini extensions; remove all extension dirs and reset enablement.
      # context7 and superpowers live here and are imported into antigravity on agy startup.
      _gemini_ext="$HOME/.gemini/extensions"
      if [ -d "$_gemini_ext" ]; then
        for _entry in "$_gemini_ext"/*; do
          [ -e "$_entry" ] || continue
          _name=$(basename "$_entry")
          [ "$_name" = "extension-enablement.json" ] && continue
          rm -rf "$_entry" || true
        done
        printf '{}' > "$_gemini_ext/extension-enablement.json" || true
      fi

      # ── Antigravity (agy) plugins ───────────────────────────────────────────
      # Keep-set is declared above as antigravityKeepPlugins = [ "playwright" ].
      # Every other entry (including *.hm-bak backup dirs) is removed.
      _agy_plugins="$HOME/.gemini/antigravity-cli/plugins"
      if [ -d "$_agy_plugins" ]; then
        for _entry in "$_agy_plugins"/*; do
          [ -e "$_entry" ] || continue
          _name=$(basename "$_entry")
          case "$_name" in
            ${antigravityKeepCases}
            *) rm -rf "$_entry" || true ;;
          esac
        done
      fi
      # Reset import manifest so agy does not reimport removed plugins.
      _agy_manifest="$HOME/.gemini/antigravity-cli/import_manifest.json"
      [ -e "$_agy_manifest" ] && printf '{"imports":[]}' > "$_agy_manifest" || true

      # ── Copilot ─────────────────────────────────────────────────────────────
      # nix declares no copilot plugins; remove installed-plugins dir entirely.
      # config.json is JSONC (// comment header); use jq to clear installedPlugins
      # while preserving trustedFolders, expAssignmentsCache, and other fields.
      _cop="$HOME/.copilot"
      if [ -d "$_cop" ]; then
        rm -rf "$_cop/installed-plugins" || true
        _cf="$_cop/config.json"
        if [ -e "$_cf" ] && command -v jq >/dev/null 2>&1; then
          _updated=$(grep -v '^//' "$_cf" | jq '.installedPlugins = []' 2>/dev/null) || true
          if [ -n "$_updated" ]; then
            {
              printf '// User settings belong in settings.json.\n'
              printf '// This file is managed automatically.\n'
              printf '%s\n' "$_updated"
            } > "$_cf" || true
          fi
        fi
      fi

      # ── Stale backups (.hm-bak and agent-created dated copies) ──────────────
      # home-manager creates *.hm-bak when replacing a file that already existed.
      # Agents create settings.json.YYYYMMDD before overwriting their config.
      # Both are dead weight once the symlinks and reconcile are in place.
      for _dir in \
        "$HOME/.claude" \
        "$HOME/.codex" \
        "$HOME/.copilot" \
        "$HOME/.gemini/antigravity-cli"; do
        [ -d "$_dir" ] || continue
        find "$_dir" -maxdepth 1 \
          \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
          -exec rm -rf {} + 2>/dev/null || true
      done

      # ── Ansible ai-role leftover ────────────────────────────────────────────
      # The disabled Ansible ai role wrote ~/.zshrc_conf/ai.sh (env vars now
      # declared in sessionVariables here). Drifted machines still have it
      # sourced on every shell; the .txt variant is a renamed leftover.
      rm -f "$HOME/.zshrc_conf/ai.sh" "$HOME/.zshrc_conf/ai.sh.txt" || true
    '';
  };
}
