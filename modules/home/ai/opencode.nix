# OpenCode: shared-instructions/reviewer symlinks, herdr plugins, tui.jsonc,
# and opencode.json (MCP, permissions). No plugin store or runtime-rewritten
# config, so nothing to reconcile.
#
# No skills link here: OpenCode discovers ~/.agents/skills natively (the hub in
# ./default.nix); a ~/.config/opencode/skills link on top would list every
# skill twice.
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

  # See ./default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@0.0.83" ];
  };
in

{
  home.file = {
    ".config/opencode/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";
    # The `reviewer` subagent named by AGENTS.md's pre-commit review.
    ".config/opencode/agents/reviewer.md".source = mkOut "${aiDir}/agents/opencode/reviewer.md";
    # Vendored from `herdr integration install opencode` (see the claude module
    # for why mkOut): the agent-state plugin, the TUI session plugin, and the
    # two entry points that load the latter.
    ".config/opencode/plugins/herdr-agent-state.js".source =
      mkOut "${aiDir}/hooks/opencode/plugins/herdr-agent-state.js";
    ".config/opencode/herdr-tui-session.js".source =
      mkOut "${aiDir}/hooks/opencode/herdr-tui-session.js";
    ".config/opencode/herdr-opencode/tui.js".source =
      mkOut "${aiDir}/hooks/opencode/herdr-opencode/tui.js";
    ".config/opencode/cli.json".source = mkOut "${aiDir}/hooks/opencode/cli.json";
    ".config/opencode/tui.jsonc".source = mkOut "${aiDir}/settings/opencode-tui.jsonc";
    # MCP servers live under the top-level "mcp" key, "command" as one array.
    # Static policy (permissions) lives in settings/opencode.json; only the MCP
    # entry, which needs a nix-store path, is added here. The file is generated
    # (not mkOut) for that reason, so a settings edit needs a rebuild. OpenCode
    # applies the last matching permission pattern, and toJSON sorts keys: "*"
    # sorts before every key there, so each catch-all is matched first (a key
    # starting with "$" or another char below "*" would break that).
    ".config/opencode/opencode.json".text = builtins.toJSON (
      lib.recursiveUpdate (lib.importJSON ../../../home/ai/settings/opencode.json) {
        mcp.playwright = {
          type = "local";
          command = [ playwrightMcp.command ] ++ playwrightMcp.args;
          enabled = true;
        };
      }
    );
  };
}
