# Codex: shared-instructions/skills symlinks, config.toml seeding/upsert,
# playwright MCP registration, and a stale-backup sweep. The Langfuse tracing
# plugin lives in ./langfuse.nix.
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

  codexModel = "gpt-5.6-sol";

  # See ../default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };

  # Codex writes its bundled system skills into ~/.codex/skills/.system/ at
  # runtime. With the whole skills dir symlinked into the repo (as every other
  # agent has it), those files landed in git. So Codex alone gets a real
  # ~/.codex/skills/ directory with one out-of-store symlink per shared skill:
  # editing a skill stays live, but adding a new skill dir needs `git add` +
  # rebuild for Codex (the list is read at eval time from the flake source).
  skillNames = builtins.attrNames (
    lib.filterAttrs (n: t: t == "directory" && !lib.hasPrefix "." n) (
      builtins.readDir ../../../../home/ai/skills
    )
  );
  codexSkillLinks = lib.listToAttrs (
    map (
      n: lib.nameValuePair ".codex/skills/${n}" { source = mkOut "${aiDir}/skills/${n}"; }
    ) skillNames
  );
in

{
  imports = [ ./langfuse.nix ];

  # Tag Codex's Langfuse traces with the launch dir; the tracing plugin reads
  # LANGFUSE_CODEX_TAGS natively. Same alias mechanics as claude's.
  programs.zsh.shellAliases.codex = ''LANGFUSE_CODEX_TAGS="codex,''${PWD:t}" codex'';

  home = {
    file = {
      ".codex/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";
    }
    // codexSkillLinks;

    activation = {
      # ~/.codex/config.toml cannot be a home.file symlink: Codex persists
      # per-directory trust decisions into this same file (a
      # [projects."<path>"] table; no separate trust file exists as of
      # codex-cli 0.144), and a read-only store symlink makes that write fail.
      # So the file is seeded/upserted here, after linkGeneration has removed
      # any old symlink.
      #
      # The `model` upsert only touches the preamble (lines before the first
      # [table] header), so the trust tables Codex writes survive every
      # rebuild by construction. awk comes from pkgs.gawk (hermetic PATH).
      #
      # MCP is registered through `codex mcp add` so Codex's own TOML writer
      # owns the table; remove-then-add for the same nix-store-path reason as
      # claude's. Nothing prunes an undeclared Codex MCP server yet - codex has
      # no list-and-prune wired up.
      codexConfig = mkReconcile {
        name = "codex-config";
        after = [ "linkGeneration" ];
        path = [ pkgs.gawk ];
        text = ''
          _codex_config="$HOME/.codex/config.toml"
          _model_line='model = "${codexModel}"'
          mkdir -p "$HOME/.codex"
          if [ ! -e "$_codex_config" ] || [ -L "$_codex_config" ]; then
            rm -f "$_codex_config"
            printf '%s\n' "$_model_line" > "$_codex_config"
          else
            awk -v model_line="$_model_line" '
              BEGIN { in_preamble = 1; wrote = 0 }
              /^\[/ {
                if (in_preamble && !wrote) { print model_line; wrote = 1 }
                in_preamble = 0
                print
                next
              }
              in_preamble && /^model[ \t]*=/ {
                print model_line
                wrote = 1
                next
              }
              { print }
              END { if (in_preamble && !wrote) print model_line }
            ' "$_codex_config" > "$_codex_config.tmp" && mv "$_codex_config.tmp" "$_codex_config"
          fi
          _codex=/opt/homebrew/bin/codex
          if [ -x "$_codex" ]; then
            "$_codex" mcp remove playwright 2>/dev/null || true
            "$_codex" mcp add playwright -- ${playwrightMcp.command} ${lib.concatStringsSep " " playwrightMcp.args} 2>/dev/null || true
          fi
        '';
      };

      # Stale backups: home-manager's *.hm-bak and the agent's own dated
      # settings.json.YYYYMMDD copies. Permanent sweep, same as the other agents.
      codexReconcile = mkReconcile {
        name = "codex-reconcile";
        text = ''
          find "$HOME/.codex" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
