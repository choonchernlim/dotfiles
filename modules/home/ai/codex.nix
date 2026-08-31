# Codex: shared-instructions/skills symlinks, config.toml seeding/upsert,
# playwright MCP registration, langfuse tracing plugin, and a stale-backup sweep.
# Deliberately self-contained - see ./default.nix for the per-agent-file convention.
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

  # The playwright MCP server Codex gets. Deliberately duplicated in every
  # ai/*.nix (self-contained agent files - see ./default.nix); when changing
  # command/args, update the copy in each agent file.
  # command is an absolute nix-store path, not bare "npx": node/npx on this machine come only
  # from mise, which puts them on PATH via its interactive-shell hook. Agents spawn MCP child
  # processes with a reduced environment that doesn't carry that hook (confirmed: codex fails
  # with "No such file or directory (os error 2)" trying to exec bare "npx"), so a PATH-based
  # lookup silently fails there. ${pkgs.nodejs}/bin/npx resolves regardless of PATH, on every
  # host (including work-atdj, which has no mise), without adding node to the interactive PATH
  # (pkgs.nodejs is referenced here only, never added to home.packages, so it can't collide
  # with mise's own node). Same fix class as the hardcoded /opt/homebrew/bin/codex path
  # and the pkgs.gawk runtime dep below.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };
in

{
  # Tag Codex's Langfuse traces with the folder it's launched in. The tracing
  # plugin (codexLangfusePlugin below) natively reads LANGFUSE_CODEX_TAGS when
  # its trace-emitting hook fires; a prefix-assignment alias sets it for just
  # that one process, evaluated at launch so ${PWD:t} is the real launch dir
  # (-> codex,<dir>). The trailing bare command name hits the real binary (zsh
  # alias-recursion guard). Declared here to keep Codex config in this module;
  # merges into zsh.nix's shellAliases (same mechanism as the claude alias in
  # ./claude.nix).
  programs.zsh.shellAliases = {
    codex = ''LANGFUSE_CODEX_TAGS="codex,''${PWD:t}" codex'';
  };

  home = {
    file = {
      # Shared instructions -> Codex's canonical filename.
      ".codex/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";

      # Shared skills dir -> Codex's skills dir.
      # force = true: existing entries are symlinks (from Ansible), not regular files,
      # so home-manager's backupFileExtension cannot move them aside automatically.
      ".codex/skills" = {
        source = mkOut "${aiDir}/skills";
        force = true;
      };
    };

    activation = {
      # Codex: unlike every other agent here, ~/.codex/config.toml cannot be a home.file
      # symlink into /nix/store. Codex persists per-directory "trust" decisions by writing
      # directly into this same file (a `[projects."<path>"] trust_level = "trusted"` table)
      # - there is no separate trust-state file as of codex-cli 0.144.4 (openai/codex#15433
      # and #14601 both ask upstream for one; neither is implemented). A read-only store
      # symlink there is exactly what produces "failed to persist config.toml ... (code
      # -32603)" when trusting a folder. So this file is deliberately seeded/upserted here
      # instead of declared in home.file, entryAfter linkGeneration so it runs after that
      # step removes the now-undeclared old symlink (never racing it).
      #
      # The `model` upsert is awk, not sed: it only ever touches the "preamble" (lines
      # before the first `[table]` header). TOML tables aren't indented, so a plain
      # `sed 's/^model = .../'` could clobber a `model` key nested in some future
      # `[table]` Codex writes at column 0. Restricting to the preamble guarantees any
      # `[projects."..."]` trust entries Codex writes at runtime survive every rebuild
      # untouched, by construction rather than by pattern-matching luck. awk comes from
      # pkgs.gawk via mkReconcile's path - home-manager's activation PATH is hermetic
      # (bash/coreutils/grep/sed/jq from the nix store only; confirmed by reading the
      # generated activate script) and does not include awk at all, on macOS or otherwise.
      #
      # MCP registration is delegated to `codex mcp add` (mirrors claudePlaywrightMcp in
      # ./claude.nix) so Codex's own TOML writer owns the `[mcp_servers.playwright]` table.
      # Remove-then-add every rebuild, same reasoning as claudePlaywrightMcp: the command is
      # a nix-store path that changes on nodejs updates, so add-if-absent would leave a stale
      # command in config.toml forever once registered once. Deliberate asymmetry vs
      # Claude/Copilot: nothing here removes an undeclared Codex MCP server on reconcile -
      # codex has no bulk list-and-prune equivalent wired yet.
      codexConfig = mkReconcile {
        name = "codex-config";
        after = [ "linkGeneration" ];
        path = [ pkgs.gawk ];
        text = ''
          _codex_config="$HOME/.codex/config.toml"
          mkdir -p "$HOME/.codex"
          if [ ! -e "$_codex_config" ] || [ -L "$_codex_config" ]; then
            rm -f "$_codex_config"
            printf 'model = "gpt-5.6-sol"\n' > "$_codex_config"
          else
            awk -v model_line='model = "gpt-5.6-sol"' '
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

      # Codex: install + enable the langfuse "tracing" plugin (marketplace + plugin) if
      # absent, mirroring claudeLangfusePlugin in ./claude.nix. entryAfter codexConfig so
      # the config.toml preamble/model upsert settles first - guard (b) below appends new
      # [table]s at EOF while codexConfig's awk only ever rewrites the preamble, so this
      # ordering means the two writes never race on the same file.
      #
      # Two independent, idempotent guards (never aborts the rebuild - all `|| true`):
      #   (a) install-if-absent: `codex plugin` has `add`, not `install` (confirmed via
      #       `codex plugin --help` on codex-cli 0.144.6). Grep the JSON text of
      #       `codex plugin list --json` rather than parse it with jq - the exact
      #       installed-entry shape wasn't worth locking to a schema. Same HTTPS-URL +
      #       /usr/bin/git reasoning as claudeLangfusePlugin in ./claude.nix: the
      #       marketplace source must be an explicit URL (the `owner/repo` shorthand
      #       resolves to an SSH clone, and the hermetic activation PATH has no `ssh`),
      #       and /usr/bin/git (macOS Keychain trust) is used instead of ${pkgs.git}
      #       (relies solely on `http.sslcainfo`, pinned on this machine to the Zscaler
      #       MITM cert - fails whenever the network path isn't actually going through
      #       Zscaler).
      #   (b) enable-if-absent, defensive fallback only: confirmed via a live rebuild that
      #       `plugin add` already writes `[plugins."tracing@codex-observability-plugin"]
      #       enabled = true` into config.toml itself, and no `[features] plugin_hooks`
      #       table is needed at all - the plugin's own README claiming otherwise turned out
      #       stale (same class of doc drift as the Claude TRACE_TO_LANGFUSE mistake noted in
      #       memory). This guard is kept only in case a future codex version stops
      #       self-writing that table; it appends both at EOF, gated on the plugin table
      #       being absent so it stays a no-op in the common case, with `[features]` gated
      #       separately so a pre-existing `[features]` table never gets a second one (TOML
      #       rejects duplicate tables).
      #
      # No keep-set needed here (unlike Claude): no reconcile sweep ever touches Codex
      # plugin state (codexReconcile below only sweeps stale backups), and codexConfig's
      # awk never rewrites past the preamble, so these tables are never at risk of being
      # pruned on a later rebuild.
      codexLangfusePlugin = mkReconcile {
        name = "codex-langfuse-plugin";
        after = [ "codexConfig" ];
        text = ''
          _codex=/opt/homebrew/bin/codex
          _cfg="$HOME/.codex/config.toml"
          if [ -x "$_codex" ]; then
            if ! "$_codex" plugin list --json 2>/dev/null | grep -q 'tracing@codex-observability-plugin'; then
              PATH="/usr/bin:$PATH" "$_codex" plugin marketplace add https://github.com/langfuse/codex-observability-plugin 2>/dev/null || true
              PATH="/usr/bin:$PATH" "$_codex" plugin add tracing@codex-observability-plugin 2>/dev/null || true
            fi
            if [ -e "$_cfg" ] && ! grep -q '^\[plugins."tracing@codex-observability-plugin"\]' "$_cfg"; then
              grep -q '^\[features\]' "$_cfg" || printf '\n[features]\nplugin_hooks = true\n' >> "$_cfg"
              printf '\n[plugins."tracing@codex-observability-plugin"]\nenabled = true\n' >> "$_cfg"
            fi
          fi
        '';
      };

      # Stale backups (.hm-bak and agent-created dated copies):
      # home-manager creates *.hm-bak when replacing a file that already existed;
      # agents create settings.json.YYYYMMDD before overwriting their config.
      # Both recur as long as agents fight the symlinks, so this sweep is
      # permanent (unlike the one-shot first-takeover .hm-baks in legacy.nix).
      # Each agent module sweeps its own config dir; for Codex that's all the
      # reconcile does - plugin/MCP state is handled by the activations above.
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
