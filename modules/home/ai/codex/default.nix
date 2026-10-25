# Codex: shared-instructions/reviewer symlinks, herdr hook, config.toml
# seeding/upsert (model, effort, secret-deny permissions profile, playwright
# MCP server), and a stale-backup sweep. The Langfuse tracing plugin lives
# in ./langfuse.nix.
#
# No skills link here: Codex discovers ~/.agents/skills natively (the hub in
# ../default.nix). ~/.codex/skills is left entirely to Codex - it writes its
# bundled system skills into ~/.codex/skills/.system/ at runtime, and a
# nix-placed symlink there once redirected those writes into the git checkout.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  home = config.home.homeDirectory;
  dotfiles = "${home}/.dotfiles";
  mkOut = config.lib.file.mkOutOfStoreSymlink;
  aiDir = "${dotfiles}/home/ai";
  mkReconcile = import ../../lib/reconcile.nix { inherit pkgs lib; };

  codexModel = "gpt-5.6-sol";

  # Top-level config.toml keys nix owns; everything else Codex writes survives.
  codexPreamble = ''
    model = "${codexModel}"
    model_reasoning_effort = "high"
    default_permissions = "dotfiles"
  '';

  # Claude's permissions.deny, as a profile on top of the built-in :workspace
  # (workspace-write). Paths are absolute: profiles have no ~ expansion. The
  # .env globs cover the whole home dir, like Claude's //**, and workspace roots
  # outside it. Network stays on: a profile ignores the
  # [sandbox_workspace_write] network_access key.
  codexPermissions = ''
    [permissions.dotfiles]
    extends = ":workspace"

    [permissions.dotfiles.network]
    enabled = true

    [permissions.dotfiles.filesystem]
    "${home}/.ssh" = "deny"
    "${home}/.gnupg" = "deny"
    "${home}/**/.env" = "deny"
    "${home}/**/.env.local" = "deny"
    "${home}/**/.env.*.local" = "deny"
    "${home}/**/.env.production" = "deny"

    [permissions.dotfiles.filesystem.":workspace_roots"]
    "**/.env" = "deny"
    "**/.env.local" = "deny"
    "**/.env.*.local" = "deny"
    "**/.env.production" = "deny"
  '';

  # See ../default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@0.0.83" ];
  };

  # "approve" runs every playwright tool without a prompt, like Claude's
  # mcp__playwright__* allow rule; the default ("auto") prompts on any tool
  # not annotated read-only, which is nearly all of them. Written by the
  # upsert because `codex mcp add` has no flag for it.
  codexMcp = ''
    [mcp_servers.playwright]
    command = "${playwrightMcp.command}"
    args = ${builtins.toJSON playwrightMcp.args}
    default_tools_approval_mode = "approve"
  '';

  # Every table the upsert owns, subtables included.
  codexTables = codexPermissions + "\n" + codexMcp;
in

{
  imports = [ ./langfuse.nix ];

  # Tag Codex's Langfuse traces with the launch dir; the tracing plugin reads
  # LANGFUSE_CODEX_TAGS natively. Same alias mechanics as claude's.
  programs.zsh.shellAliases.codex = ''LANGFUSE_CODEX_TAGS="codex,''${PWD:t}" codex'';

  home = {
    file = {
      ".codex/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";
      # The `reviewer` subagent named by AGENTS.md's pre-commit review.
      ".codex/agents/reviewer.toml".source = mkOut "${aiDir}/agents/codex/reviewer.toml";
      # Vendored from `herdr integration install codex`; hooks.json calls it
      # (see the claude module for why mkOut). Codex keeps hook trust in
      # config.toml, never in hooks.json, so a symlink is safe here.
      ".codex/herdr-agent-state.sh".source = mkOut "${aiDir}/hooks/codex/herdr-agent-state.sh";
      ".codex/hooks.json".source = mkOut "${aiDir}/settings/codex-hooks.json";
    };

    activation = {
      # ~/.codex/config.toml cannot be a home.file symlink: Codex persists
      # per-directory trust decisions into this same file (a
      # [projects."<path>"] table; no separate trust file exists as of
      # codex-cli 0.144), and a read-only store symlink makes that write fail.
      # So the file is seeded/upserted here, after linkGeneration has removed
      # any old symlink.
      #
      # The upsert owns only codexPreamble's keys (rewritten at the top of the
      # file) and codexTables' tables and their subtables (re-appended at EOF);
      # the trust tables Codex writes survive every rebuild by construction.
      # awk comes from pkgs.gawk (hermetic PATH). Nothing prunes an undeclared
      # Codex MCP server yet.
      codexConfig = mkReconcile {
        name = "codex-config";
        after = [ "linkGeneration" ];
        path = [ pkgs.gawk ];
        text = ''
          _codex_config="$HOME/.codex/config.toml"
          _preamble='${lib.removeSuffix "\n" codexPreamble}'
          _tables='${lib.removeSuffix "\n" codexTables}'
          mkdir -p "$HOME/.codex"
          if [ ! -e "$_codex_config" ] || [ -L "$_codex_config" ]; then
            rm -f "$_codex_config"
            : > "$_codex_config"
          fi
          _apply "$_codex_config" awk -v preamble="$_preamble" -v tables="$_tables" '
            BEGIN {
              n = split(preamble, lines, "\n")
              for (i = 1; i <= n; i++) { k = lines[i]; sub(/[ \t]*=.*/, "", k); owned[k] = 1; print lines[i] }
              n = split(tables, lines, "\n")
              for (i = 1; i <= n; i++) if (lines[i] ~ /^\[/) owned_tables[header(lines[i])] = 1
              in_preamble = 1; skip = 0; blanks = 0
            }
            # A header line as a comparable key path: no brackets, comment, or
            # CR, no spaces around dots, and bare-key-safe quotes dropped, so
            # [ mcp_servers."playwright" ] still matches [mcp_servers.playwright].
            function header(s) {
              sub(/\r$/, "", s); sub(/^\[+[ \t]*/, "", s); sub(/[ \t]*\]+[ \t]*(#.*)?$/, "", s)
              gsub(/[ \t]*\.[ \t]*/, ".", s)
              return gensub(/"([A-Za-z0-9_-]+)"/, "\\1", "g", s)
            }
            # Owned: an owned table or a subtable of one.
            function owns(s,   t) { s = header(s); for (t in owned_tables) if (s == t || index(s, t ".") == 1) return 1; return 0 }
            # Blank lines are held back so dropped lines never leave a growing gap.
            function emit(s) { while (blanks > 0) { print ""; blanks-- } print s }
            # Lines inside a multi-line string are data, never headers or keys:
            # an odd count of triple quotes (\047 is a single quote) toggles it.
            function quotes(s) { return gsub(/"""|\047\047\047/, "", s) % 2 }
            in_string { if (!skip) emit($0); if (quotes($0)) in_string = 0; next }
            quotes($0) { in_string = 1 }
            /^\[/ { in_preamble = 0; skip = owns($0) }
            skip { next }
            /^[ \t]*$/ { blanks++; next }
            in_preamble { k = $0; sub(/[ \t]*=.*/, "", k); if (k in owned) next }
            { emit($0) }
            END { print ""; print tables }
          ' || true
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
