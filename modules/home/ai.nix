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

  # Single source of truth for the playwright MCP server every agent gets.
  # Each agent's native config format is rendered from this below - change once, propagates everywhere.
  # command is an absolute nix-store path, not bare "npx": node/npx on this machine come only
  # from mise, which puts them on PATH via its interactive-shell hook. Agents spawn MCP child
  # processes with a reduced environment that doesn't carry that hook (confirmed: codex fails
  # with "No such file or directory (os error 2)" trying to exec bare "npx"), so a PATH-based
  # lookup silently fails there. ${pkgs.nodejs}/bin/npx resolves regardless of PATH, on every
  # host (including work-atdj, which has no mise), without adding node to the interactive PATH
  # (pkgs.nodejs is referenced here only, never added to home.packages, so it can't collide
  # with mise's own node). Same fix class as the hardcoded /opt/homebrew/bin/claude and
  # ${pkgs.gawk}/bin/awk paths below.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };

  # Antigravity plugin dir, assembled as ONE leaf (a directory derivation) rather than
  # per-file home.file entries: the existing plugins/playwright path is a directory-symlink
  # left over from the pre-unification layout, and home-manager's activation script can't
  # mkdir -p through an existing symlink to place per-file entries inside it (force = true
  # only overrides leaf-file collisions, not this structural case). linkFarm keeps the same
  # single-leaf-symlink shape that force = true already handles correctly (see skills below).
  playwrightAntigravityPlugin = pkgs.linkFarm "antigravity-playwright-plugin" [
    {
      name = "mcp_config.json";
      path = pkgs.writeText "mcp_config.json" (
        builtins.toJSON {
          mcpServers.playwright = {
            inherit (playwrightMcp) command args;
          };
        }
      );
    }
    {
      name = "plugin.json";
      path = pkgs.writeText "plugin.json" (builtins.toJSON { name = "playwright"; });
    }
  ];

  # Nix-declared antigravity plugin names (basenames under ~/.gemini/antigravity-cli/plugins/).
  # The aiReconcile sweep removes every other entry.
  # To add a plugin: declare its source in home.file above AND add its name here.
  antigravityKeepPlugins = [ "playwright" ];

  # Shell case-branches generated from the keep-set used by the reconcile sweep.
  # Each branch matches a plugin basename and skips it (continue).
  antigravityKeepCases = lib.concatMapStringsSep "\n        " (
    p: ''"${p}") continue ;;''
  ) antigravityKeepPlugins;

  # Nix-declared Claude plugins/marketplaces that aiReconcile preserves instead of wiping.
  # Installed imperatively via `claude plugin marketplace add` / `claude plugin install` -
  # the plugin's own installer writes installed_plugins.json/known_marketplaces.json/cache
  # dirs; nix only guards the declared keys from the reconcile sweep below (same pattern as
  # antigravityKeepPlugins). To add another plugin: install it, then add its "name@marketplace"
  # key here and its marketplace name to claudeKeepMarketplaces.
  claudeKeepInstalled = [ "langfuse-observability@langfuse-observability" ];
  claudeKeepMarketplaces = [ "langfuse-observability" ];
  claudeKeepInstalledJson = builtins.toJSON claudeKeepInstalled;
  claudeKeepMarketplacesJson = builtins.toJSON claudeKeepMarketplaces;

  # Shell case-branches for the marketplaces/ and cache/ dir sweep, keyed by marketplace name.
  claudeKeepMarketplaceCases = lib.concatMapStringsSep "\n              " (
    p: ''"${p}") continue ;;''
  ) claudeKeepMarketplaces;

  # Local patch giving the installed langfuse-observability plugin a custom-tag env
  # var (CC_LANGFUSE_TAGS), which upstream 1.0.0 has no equivalent of - its
  # get_trace_tags() only ever returns ["claude-code"] + auto skill:<name> tags.
  # Mirrors the Codex plugin's existing LANGFUSE_CODEX_TAGS support. Inserted by
  # claudeLangfuseTagsPatch below, just before the `if __name__ == "__main__":`
  # guard - the module calls main() at EOF, so appending after that point would
  # never run. Rebinds the module-global `get_trace_tags` (referenced by name at
  # its call site further up the file, so the rebinding takes effect at call time)
  # rather than editing the original function body, keeping the patch a pure
  # insertion - no line inside the upstream file is touched or reflowed.
  # TEMPORARY: a stopgap to validate the tagging behavior now; see the "Staging"
  # note in the plan this shipped from. Once confirmed, the plan is to move this
  # into a fork of the plugin (or upstream it) and drop this activation entirely -
  # at that point only the marketplace URL in claudeLangfusePlugin changes; the
  # CC_LANGFUSE_TAGS env var and the `claude` shellAlias below stay as-is.
  claudeTagsPatch = pkgs.writeText "claude-langfuse-cc-tags-patch.py" ''
    # --- nix-managed: CC_LANGFUSE_TAGS support (dotfiles modules/home/ai.nix) ---
    _orig_get_trace_tags = get_trace_tags


    def get_trace_tags(*args, **kwargs):
        tags = _orig_get_trace_tags(*args, **kwargs)
        _custom = _opt("CC_LANGFUSE_TAGS")
        if _custom:
            tags = tags + [t.strip() for t in _custom.split(",") if t.strip()]
        return tags


    # --- end nix-managed: CC_LANGFUSE_TAGS support ---
  '';
in

{
  # Tag Codex's and Claude's Langfuse traces with the folder each is launched in.
  # Both plugins (codexLangfusePlugin / claudeLangfusePlugin + claudeTagsPatch
  # below) read a *_TAGS env var when their trace-emitting hook fires; a
  # prefix-assignment alias sets it for just that one process, evaluated at
  # launch so ${PWD:t} is the real launch dir. The trailing bare command name
  # hits the real binary (zsh alias-recursion guard). Declared here to keep AI
  # config in this module; merges into zsh.nix's shellAliases.
  #   - codex: LANGFUSE_CODEX_TAGS is native to the Codex plugin -> codex,<dir>.
  #   - claude: CC_LANGFUSE_TAGS only exists because of the claudeTagsPatch
  #     activation below (upstream 1.0.0 has no custom-tag var); its own
  #     "claude-code" base tag is already automatic, so just <dir> here.
  programs.zsh.shellAliases = {
    codex = ''LANGFUSE_CODEX_TAGS="codex,''${PWD:t}" codex'';
    claude = ''CC_LANGFUSE_TAGS="''${PWD:t}" claude'';
  };

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

      # Per-agent settings, rendered from playwrightMcp above where an MCP server is involved.
      {
        ".claude/settings.json".source = mkOut "${aiDir}/settings/claude.json";
        ".gemini/antigravity-cli/settings.json".source = mkOut "${aiDir}/settings/antigravity.json";
        ".copilot/settings.json".source = mkOut "${aiDir}/settings/copilot.json";

        # Copilot MCP: JSON, mcpServers.<name>
        ".copilot/mcp-config.json".text = builtins.toJSON {
          mcpServers.playwright = {
            type = "local";
            inherit (playwrightMcp) command args;
            tools = [ "*" ];
          };
        };

        # Antigravity plugin dir: one leaf symlink to the linkFarm assembled above.
        ".gemini/antigravity-cli/plugins/playwright" = {
          source = playwrightAntigravityPlugin;
          force = true;
        };

        # OpenCode: MCP servers live under the top-level "mcp" key, "command" as a single array.
        ".config/opencode/opencode.json".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          mcp.playwright = {
            type = "local";
            command = [ playwrightMcp.command ] ++ playwrightMcp.args;
            enabled = true;
          };
        };

        # rtk hook integrations (declarative - rtk init never runs on this system)
        ".copilot/hooks/rtk-rewrite.json".source = mkOut "${aiDir}/hooks/copilot/rtk-rewrite.json";
        ".config/opencode/plugins/rtk.ts".source = mkOut "${aiDir}/hooks/opencode/rtk.ts";
      }
    ];

    sessionVariables = {
      ANTHROPIC_MODEL = "opusplan";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-8";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-5";
    };

    activation = {
      # Register playwright MCP for Claude (stored in ~/.claude.json, not symlinkable).
      # Remove-then-add every rebuild (not add-if-absent): playwrightMcp.command is a nix-store
      # path that changes on every nodejs update, so an add-if-absent guard would leave a stale
      # registered command on disk forever once it's registered once. remove is a no-op (|| true)
      # when nothing is registered, making this idempotent either way. No-op if claude is not
      # installed. Absolute path, not `command -v` - home-manager's activation PATH is hermetic
      # (bash/coreutils/grep/sed/jq from the nix store only, confirmed via the generated activate
      # script), it never includes /opt/homebrew/bin, so a PATH-based lookup here always silently
      # no-ops. Same fix ghostty.nix already uses for its own brew invocation.
      claudePlaywrightMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _claude=/opt/homebrew/bin/claude
        if [ -x "$_claude" ]; then
          "$_claude" mcp remove --scope user playwright 2>/dev/null || true
          "$_claude" mcp add --scope user playwright -- ${playwrightMcp.command} ${lib.concatStringsSep " " playwrightMcp.args} || true
        fi
      '';

      # Claude: install the langfuse-observability plugin (marketplace + plugin) if it's
      # absent, so the keep-set above has something to preserve on a fresh/wiped machine
      # instead of only ever guarding an already-installed plugin. Check-if-absent, not
      # remove-then-add like claudePlaywrightMcp above - a plugin install has no nix-store
      # path that churns on every rebuild, so re-running it every time would just be a
      # wasted network round-trip (marketplace git clone + plugin fetch). Absolute path,
      # not `command -v` - see claudePlaywrightMcp above for why.
      #
      # The marketplace source is an explicit HTTPS URL, not the `owner/repo` shorthand -
      # the CLI resolves that shorthand to an SSH clone (git@github.com:...), which needs the
      # user's SSH agent and always fails silently under `|| true` here: home-manager's
      # activation PATH is hermetic and carries no `ssh` at all (confirmed via the generated
      # activate script - bash/coreutils/diffutils/findutils/gettext/grep/sed/jq/ncurses only).
      # HTTPS needs no credentials for this public repo. `git` itself is also absent from that
      # PATH, so /usr/bin/git (Xcode CLT, present per bootstrap.sh's CLT check) is prepended
      # locally for just this command - not ${pkgs.git}: that hermetic build has no bundled CA
      # trust and relies on `http.sslcainfo`, which on this machine points at the Zscaler MITM
      # cert only (modules/home/zscaler.nix) and fails TLS verification whenever the network
      # path isn't actually going through Zscaler at that moment (the real GitHub cert chain
      # isn't rooted in that cert). /usr/bin/git instead validates against the macOS Keychain
      # trust store, which is correct on every network path.
      claudeLangfusePlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _claude=/opt/homebrew/bin/claude
        _ip="$HOME/.claude/plugins/installed_plugins.json"
        if [ -x "$_claude" ]; then
          if ! jq -e '.plugins["langfuse-observability@langfuse-observability"]' "$_ip" >/dev/null 2>&1; then
            PATH="/usr/bin:$PATH" "$_claude" plugin marketplace add https://github.com/langfuse/Claude-Observability-Plugin 2>/dev/null || true
            PATH="/usr/bin:$PATH" "$_claude" plugin install langfuse-observability@langfuse-observability 2>/dev/null || true
          fi
        fi
      '';

      # Claude: give the installed langfuse plugin CC_LANGFUSE_TAGS support (see
      # claudeTagsPatch above for why - upstream 1.0.0 has no custom-tag env var).
      # entryAfter claudeLangfusePlugin so the plugin is installed first. Marker-
      # guarded (grep before patching) so a rebuild never inserts a second copy,
      # and a fresh reinstall (undeclared-plugin wipe + reinstall) is re-patched
      # automatically on the next rebuild. Globs every version dir under cache/,
      # not just 1.0.0, so a future plugin upgrade is still patched without an
      # edit here (though the insertion point - just before the __main__ guard -
      # is an assumption about upstream's file layout and could need revisiting
      # if that layout changes).
      claudeLangfuseTagsPatch = lib.hm.dag.entryAfter [ "writeBoundary" "claudeLangfusePlugin" ] ''
        for _hook in "$HOME"/.claude/plugins/cache/langfuse-observability/langfuse-observability/*/hooks/langfuse_hook.py; do
          [ -e "$_hook" ] || continue
          grep -q 'nix-managed: CC_LANGFUSE_TAGS support' "$_hook" && continue
          if ${pkgs.gawk}/bin/awk -v pf='${claudeTagsPatch}' '
               /^if __name__ == "__main__":/ && !ins { while ((getline l < pf) > 0) print l; close(pf); ins=1 }
               { print }
             ' "$_hook" > "$_hook.tmp" && [ -s "$_hook.tmp" ]; then
            mv "$_hook.tmp" "$_hook"
          else
            rm -f "$_hook.tmp" || true
          fi
        done
      '';

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
      # untouched, by construction rather than by pattern-matching luck. Referenced via
      # ${pkgs.gawk}/bin/awk, not bare `awk` - home-manager's activation PATH is hermetic
      # (bash/coreutils/grep/sed/jq from the nix store only; confirmed by reading the
      # generated activate script) and does not include awk at all, on macOS or otherwise.
      #
      # MCP registration is delegated to `codex mcp add` (mirrors claudePlaywrightMcp
      # above) so Codex's own TOML writer owns the `[mcp_servers.playwright]` table.
      # Remove-then-add every rebuild, same reasoning as claudePlaywrightMcp: the command is
      # a nix-store path that changes on nodejs updates, so add-if-absent would leave a stale
      # command in config.toml forever once registered once. Deliberate asymmetry vs
      # Claude/Copilot: nothing here removes an undeclared Codex MCP server on reconcile -
      # codex has no bulk list-and-prune equivalent wired yet.
      codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
        _codex_config="$HOME/.codex/config.toml"
        mkdir -p "$HOME/.codex"
        if [ ! -e "$_codex_config" ] || [ -L "$_codex_config" ]; then
          rm -f "$_codex_config"
          printf 'model = "gpt-5.6-sol"\n' > "$_codex_config"
        else
          ${pkgs.gawk}/bin/awk -v model_line='model = "gpt-5.6-sol"' '
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

      # Codex: install + enable the langfuse "tracing" plugin (marketplace + plugin) if
      # absent, mirroring claudeLangfusePlugin above. entryAfter codexConfig so the
      # config.toml preamble/model upsert settles first - guard (b) below appends new
      # [table]s at EOF while codexConfig's awk only ever rewrites the preamble, so this
      # ordering means the two writes never race on the same file.
      #
      # Two independent, idempotent guards (never aborts the rebuild - all `|| true`):
      #   (a) install-if-absent: `codex plugin` has `add`, not `install` (confirmed via
      #       `codex plugin --help` on codex-cli 0.144.6). Grep the JSON text of
      #       `codex plugin list --json` rather than parse it with jq - the exact
      #       installed-entry shape wasn't worth locking to a schema. Same HTTPS-URL +
      #       /usr/bin/git reasoning as claudeLangfusePlugin above: the marketplace source
      #       must be an explicit URL (the `owner/repo` shorthand resolves to an SSH clone,
      #       and the hermetic activation PATH has no `ssh`), and /usr/bin/git (macOS
      #       Keychain trust) is used instead of ${pkgs.git} (relies solely on
      #       `http.sslcainfo`, pinned on this machine to the Zscaler MITM cert - fails
      #       whenever the network path isn't actually going through Zscaler).
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
      # No keep-set needed here (unlike Claude): aiReconcile never touches Codex plugin
      # state, and codexConfig's awk never rewrites past the preamble, so these tables are
      # never at risk of being pruned on a later rebuild.
      codexLangfusePlugin = lib.hm.dag.entryAfter [ "writeBoundary" "codexConfig" ] ''
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

      # Enforce nix as the single source of truth for all AI-agent plugins, extensions, and MCP,
      # with one declared exception: Claude plugins/marketplaces in claudeKeepInstalled /
      # claudeKeepMarketplaces above (installed imperatively via `claude plugin install`, then
      # kept alive here - same pattern as antigravityKeepPlugins). Everything else not declared
      # is removed. Runs on every rebuild after claudePlaywrightMcp and claudeLangfusePlugin (so
      # playwright is registered and langfuse is installed first). Adding a capability must be
      # done in nix (or, for Claude, installed then added to
      # the keep-set); an undeclared out-of-band install is reverted on the next rebuild.
      #
      # Mechanism (hybrid):
      #   - Claude plugins: keep-set prune (installed_plugins.json + known_marketplaces.json +
      #     marketplaces/cache dirs) instead of a blanket reset, so a declared plugin survives.
      #     MCP registry in ~/.claude.json must go through the CLI (claude mcp remove).
      #   - Gemini extensions, antigravity, copilot: filesystem + JSON reset (antigravity also
      #     has its own keep-set). Their CLIs are networked or disagree with on-disk state
      #     (unreliable offline).
      #
      # Safety: every rm is on an explicit quoted path; [ -e ] or find guards prevent abort
      # on missing files; || true keeps a transient failure from killing the whole rebuild.
      aiReconcile =
        lib.hm.dag.entryAfter [ "writeBoundary" "claudePlaywrightMcp" "claudeLangfusePlugin" ]
          ''
            # ── Claude: plugin store + undeclared MCP ──────────────────────────────
            # Plugin JSON state files live under ~/.claude/plugins/ which we own directly.
            # ~/.claude.json (MCP registry) must be mutated via the claude CLI, not by hand.
            _claude_plugins="$HOME/.claude/plugins"
            if [ -d "$_claude_plugins" ]; then
              _ip="$_claude_plugins/installed_plugins.json"
              if [ -e "$_ip" ]; then
                _pruned=$(jq --argjson keep '${claudeKeepInstalledJson}' \
                  '.version = (.version // 2) | .plugins = ((.plugins // {}) | with_entries(select(.key as $k | $keep | index($k))))' \
                  "$_ip" 2>/dev/null) || true
                [ -n "$_pruned" ] && printf '%s\n' "$_pruned" > "$_ip" || true
              else
                printf '{"version":2,"plugins":{}}' > "$_ip" || true
              fi
              _km="$_claude_plugins/known_marketplaces.json"
              if [ -e "$_km" ]; then
                _pruned=$(jq --argjson keep '${claudeKeepMarketplacesJson}' \
                  'with_entries(select(.key as $k | $keep | index($k)))' \
                  "$_km" 2>/dev/null) || true
                [ -n "$_pruned" ] && printf '%s\n' "$_pruned" > "$_km" || true
              else
                printf '{}' > "$_km" || true
              fi
              for _base in marketplaces cache; do
                _dir="$_claude_plugins/$_base"
                [ -d "$_dir" ] || continue
                for _entry in "$_dir"/*; do
                  [ -e "$_entry" ] || continue
                  _name=$(basename "$_entry")
                  case "$_name" in
                    ${claudeKeepMarketplaceCases}
                    *) rm -rf "$_entry" || true ;;
                  esac
                done
              done
            fi
            # Absolute path, not `command -v` - see claudePlaywrightMcp above for why.
            _claude=/opt/homebrew/bin/claude
            if [ -x "$_claude" ]; then
              "$_claude" mcp remove --scope user context7 2>/dev/null || true
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
          '';
    };
  };
}
