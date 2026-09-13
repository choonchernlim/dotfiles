# OpenCode: shared-instructions/skills symlinks and opencode.json (MCP).
# No plugin store or runtime-rewritten config, so nothing to reconcile.
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
    # force: pre-nix entries here were symlinks, which home-manager's
    # backupFileExtension cannot move aside on its own.
    ".config/opencode/skills" = {
      source = mkOut "${aiDir}/skills";
      force = true;
    };
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
