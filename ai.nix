{ config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";
in

{
  # Shared instructions -> each agent's canonical filename
  home.file = lib.mkMerge [
    (lib.genAttrs [
      ".claude/CLAUDE.md"
      ".codex/AGENTS.md"
      ".config/opencode/AGENTS.md"
      ".gemini/antigravity-cli/ANTIGRAVITY.md"
      ".copilot/copilot-instructions.md"
    ] (_: { source = mkOut "${aiDir}/AGENTS.md"; }))

    # Shared skills dir -> each agent's skills dir
    # force = true: existing entries are symlinks (from Ansible), not regular files,
    # so home-manager's backupFileExtension cannot move them aside automatically.
    (lib.genAttrs [
      ".claude/skills"
      ".codex/skills"
      ".config/opencode/skills"
      ".gemini/antigravity-cli/skills"
      ".copilot/skills"
    ] (_: { source = mkOut "${aiDir}/skills"; force = true; }))

    # Per-agent settings and MCP configs
    {
      ".claude/settings.json".source =
        mkOut "${aiDir}/settings/claude.json";
      ".gemini/antigravity-cli/settings.json".source =
        mkOut "${aiDir}/settings/antigravity.json";
      ".copilot/settings.json".source =
        mkOut "${aiDir}/settings/copilot.json";
      ".copilot/mcp-config.json".source =
        mkOut "${aiDir}/mcp/copilot/mcp-config.json";
      ".codex/config.toml".source =
        mkOut "${aiDir}/mcp/codex/config.toml";
      ".gemini/antigravity-cli/plugins/playwright".source =
        mkOut "${aiDir}/mcp/antigravity/playwright";
    }
  ];

  home.sessionVariables = {
    ANTHROPIC_MODEL = "opusplan";
    ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-7";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-6";
  };

  # Register playwright MCP for Claude (stored in ~/.claude.json, not symlinkable).
  # Guard: no-op if already registered or if claude is not on PATH during activation.
  home.activation.claudePlaywrightMcp =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v claude >/dev/null 2>&1; then
        if ! claude mcp list 2>/dev/null | grep -q '^playwright'; then
          claude mcp add --scope user playwright -- npx @playwright/mcp@latest || true
        fi
      fi
    '';
}
