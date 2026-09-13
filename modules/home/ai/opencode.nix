# OpenCode: shared-instructions symlink and opencode.json (MCP). No plugin
# store or runtime-rewritten config, so nothing to reconcile.
#
# No skills link here: OpenCode discovers ~/.agents/skills natively (the hub in
# ./default.nix); a ~/.config/opencode/skills link on top would list every
# skill twice.
{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";

  # See ./default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };
in

{
  home.file = {
    ".config/opencode/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";
    # MCP servers live under the top-level "mcp" key, "command" as one array.
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
