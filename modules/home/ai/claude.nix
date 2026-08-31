# Claude Code: shared-instructions/skills/settings symlinks, model env vars,
# playwright MCP registration, langfuse plugin install + tags patch, and the
# reconcile sweep keeping ~/.claude plugin state nix-declared.
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

  # The playwright MCP server Claude gets. Deliberately duplicated in every
  # ai/*.nix (self-contained agent files - see ./default.nix); when changing
  # command/args, update the copy in each agent file.
  # command is an absolute nix-store path, not bare "npx": node/npx on this machine come only
  # from mise, which puts them on PATH via its interactive-shell hook. Agents spawn MCP child
  # processes with a reduced environment that doesn't carry that hook (confirmed: codex fails
  # with "No such file or directory (os error 2)" trying to exec bare "npx"), so a PATH-based
  # lookup silently fails there. ${pkgs.nodejs}/bin/npx resolves regardless of PATH, on every
  # host (including work-atdj, which has no mise), without adding node to the interactive PATH
  # (pkgs.nodejs is referenced here only, never added to home.packages, so it can't collide
  # with mise's own node). Same fix class as the hardcoded /opt/homebrew/bin/claude path below.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@latest" ];
  };

  # Nix-declared Claude plugins/marketplaces that claudeReconcile preserves instead of wiping.
  # Installed imperatively via `claude plugin marketplace add` / `claude plugin install` -
  # the plugin's own installer writes installed_plugins.json/known_marketplaces.json/cache
  # dirs; nix only guards the declared keys from the reconcile sweep below (same pattern as
  # antigravityKeepPlugins in ./antigravity.nix). To add another plugin: install it, then add
  # its "name@marketplace" key here and its marketplace name to claudeKeepMarketplaces.
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
  # Mirrors the Codex plugin's existing LANGFUSE_CODEX_TAGS support (see
  # ./codex.nix). Inserted by claudeLangfuseTagsPatch below, just before the
  # `if __name__ == "__main__":` guard - the module calls main() at EOF, so
  # appending after that point would never run. Rebinds the module-global
  # `get_trace_tags` (referenced by name at its call site further up the file,
  # so the rebinding takes effect at call time) rather than editing the original
  # function body, keeping the patch a pure insertion - no line inside the
  # upstream file is touched or reflowed.
  # TEMPORARY: a stopgap to validate the tagging behavior now; see the "Staging"
  # note in the plan this shipped from. Once confirmed, the plan is to move this
  # into a fork of the plugin (or upstream it) and drop this activation entirely -
  # at that point only the marketplace URL in claudeLangfusePlugin changes; the
  # CC_LANGFUSE_TAGS env var and the `claude` shellAlias below stay as-is.
  claudeTagsPatch = pkgs.writeText "claude-langfuse-cc-tags-patch.py" ''
    # --- nix-managed: CC_LANGFUSE_TAGS support (dotfiles modules/home/ai/claude.nix) ---
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
  # Tag Claude's Langfuse traces with the folder it's launched in. The langfuse
  # plugin (claudeLangfusePlugin + claudeLangfuseTagsPatch below) reads
  # CC_LANGFUSE_TAGS when its trace-emitting hook fires; a prefix-assignment
  # alias sets it for just that one process, evaluated at launch so ${PWD:t} is
  # the real launch dir. The trailing bare command name hits the real binary
  # (zsh alias-recursion guard). CC_LANGFUSE_TAGS only exists because of the
  # claudeLangfuseTagsPatch activation below (upstream 1.0.0 has no custom-tag
  # var); the plugin's own "claude-code" base tag is already automatic, so just
  # <dir> here. Declared here to keep Claude config in this module; merges into
  # zsh.nix's shellAliases (same mechanism as the codex alias in ./codex.nix).
  programs.zsh.shellAliases = {
    claude = ''CC_LANGFUSE_TAGS="''${PWD:t}" claude'';
  };

  home = {
    file = {
      # Shared instructions -> Claude's canonical filename.
      ".claude/CLAUDE.md".source = mkOut "${aiDir}/AGENTS.md";

      # Shared skills dir -> Claude's skills dir.
      # force = true: existing entries are symlinks (from Ansible), not regular files,
      # so home-manager's backupFileExtension cannot move them aside automatically.
      ".claude/skills" = {
        source = mkOut "${aiDir}/skills";
        force = true;
      };

      ".claude/settings.json".source = mkOut "${aiDir}/settings/claude.json";
    };

    sessionVariables = {
      ANTHROPIC_MODEL = "opusplan";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-5";
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
      # no-ops - hence the absolute /opt/homebrew/bin/claude path below.
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
      claudeLangfusePlugin = mkReconcile {
        name = "claude-langfuse-plugin";
        text = ''
          _claude=/opt/homebrew/bin/claude
          _ip="$HOME/.claude/plugins/installed_plugins.json"
          if [ -x "$_claude" ]; then
            if ! jq -e '.plugins["langfuse-observability@langfuse-observability"]' "$_ip" >/dev/null 2>&1; then
              PATH="/usr/bin:$PATH" "$_claude" plugin marketplace add https://github.com/langfuse/Claude-Observability-Plugin 2>/dev/null || true
              PATH="/usr/bin:$PATH" "$_claude" plugin install langfuse-observability@langfuse-observability 2>/dev/null || true
            fi
          fi
        '';
      };

      # Claude: give the installed langfuse plugin CC_LANGFUSE_TAGS support (see
      # claudeTagsPatch above for why - upstream 1.0.0 has no custom-tag env var).
      # entryAfter claudeLangfusePlugin so the plugin is installed first. Guarded
      # (grep before patching) so a rebuild never inserts a second copy, and a
      # fresh reinstall (undeclared-plugin wipe + reinstall) is re-patched
      # automatically on the next rebuild. Globs every version dir under cache/,
      # not just 1.0.0, so a future plugin upgrade is still patched without an
      # edit here (though the insertion point - just before the __main__ guard -
      # is an assumption about upstream's file layout and could need revisiting
      # if that layout changes).
      #
      # The guard matches EITHER our own marker comment OR a call reading the
      # CC_LANGFUSE_TAGS env var - not just the marker. Without the second
      # alternative, pointing the plugin's marketplace at a fork/build that
      # already has CC_LANGFUSE_TAGS support (no marker comment, since it's not
      # our patch) would look "unpatched" to this grep and get a second wrapper
      # stacked on top, double-appending every custom tag. Same gap would
      # otherwise resurface once upstream ships this feature for real, so the
      # dual guard is a permanent fix, not just a fork-testing workaround.
      # Matches on `_opt("CC_LANGFUSE_TAGS")` - the env var name itself, i.e. the
      # actual config contract - rather than on a variable name like
      # `CUSTOM_TAGS` some particular implementation happens to store it in:
      # variable names are an implementation detail a maintainer could rename
      # during review (e.g. merging this repo's own upstream PR under a
      # different name), which would silently break a marker keyed on it.
      claudeLangfuseTagsPatch = mkReconcile {
        name = "claude-langfuse-tags-patch";
        after = [ "claudeLangfusePlugin" ];
        path = [ pkgs.gawk ];
        text = ''
          for _hook in "$HOME"/.claude/plugins/cache/langfuse-observability/langfuse-observability/*/hooks/langfuse_hook.py; do
            [ -e "$_hook" ] || continue
            grep -qE 'nix-managed: CC_LANGFUSE_TAGS support|_opt\("CC_LANGFUSE_TAGS"\)' "$_hook" && continue
            if awk -v pf='${claudeTagsPatch}' '
                 /^if __name__ == "__main__":/ && !ins { while ((getline l < pf) > 0) print l; close(pf); ins=1 }
                 { print }
               ' "$_hook" > "$_hook.tmp" && [ -s "$_hook.tmp" ]; then
              mv "$_hook.tmp" "$_hook"
            else
              rm -f "$_hook.tmp"
            fi
          done
        '';
      };

      # Enforce nix as the single source of truth for Claude plugins and MCP, with one
      # declared exception: the plugins/marketplaces in claudeKeepInstalled /
      # claudeKeepMarketplaces above (installed imperatively via `claude plugin install`,
      # then kept alive here - same pattern as antigravityKeepPlugins in ./antigravity.nix).
      # Everything else not declared is removed on every rebuild; an undeclared
      # out-of-band install is reverted. Runs after claudePlaywrightMcp and
      # claudeLangfusePlugin so playwright is registered and langfuse is installed first.
      #
      # Mechanism: keep-set prune of the plugin JSON state (installed_plugins.json +
      # known_marketplaces.json) and the marketplaces/cache dirs instead of a blanket
      # reset, so a declared plugin survives. The MCP registry in ~/.claude.json must be
      # mutated via the claude CLI (claude mcp remove), not by hand.
      #
      # Safety: every rm is on an explicit quoted path; [ -e ]/[ -d ] guards skip missing
      # files; JSON state files are rewritten atomically via json_edit (mkReconcile's
      # tmp+mv helper) so an interrupt never corrupts a file agents also read.
      claudeReconcile = mkReconcile {
        name = "claude-reconcile";
        after = [
          "claudePlaywrightMcp"
          "claudeLangfusePlugin"
        ];
        text = ''
          _claude_plugins="$HOME/.claude/plugins"
          if [ -d "$_claude_plugins" ]; then
            _ip="$_claude_plugins/installed_plugins.json"
            if [ -e "$_ip" ]; then
              json_edit "$_ip" --argjson keep '${claudeKeepInstalledJson}' \
                '.version = (.version // 2) | .plugins = ((.plugins // {}) | with_entries(select(.key as $k | $keep | index($k))))'
            else
              printf '{"version":2,"plugins":{}}' > "$_ip"
            fi
            _km="$_claude_plugins/known_marketplaces.json"
            if [ -e "$_km" ]; then
              json_edit "$_km" --argjson keep '${claudeKeepMarketplacesJson}' \
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
          # Absolute path, not `command -v` - see claudePlaywrightMcp above for why.
          _claude=/opt/homebrew/bin/claude
          if [ -x "$_claude" ]; then
            "$_claude" mcp remove --scope user context7 2>/dev/null || true
          fi

          # Stale backups (.hm-bak and agent-created dated copies):
          # home-manager creates *.hm-bak when replacing a file that already existed;
          # agents create settings.json.YYYYMMDD before overwriting their config.
          # Both recur as long as agents fight the symlinks, so this sweep is
          # permanent (unlike the one-shot first-takeover .hm-baks in legacy.nix).
          # Each agent module sweeps its own config dir.
          find "$HOME/.claude" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
