# Antigravity (agy): shared-instructions/skills symlinks, playwright plugin,
# settings merge-reconcile, self-update, and the reconcile sweep covering both
# antigravity's own plugin store AND ~/.gemini/extensions (Gemini CLI), the
# root import source agy reimports plugins from on startup.
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

  # The playwright MCP server antigravity gets. Deliberately duplicated in every
  # ai/*.nix (self-contained agent files - see ./default.nix); when changing
  # command/args, update the copy in each agent file.
  # command is an absolute nix-store path, not bare "npx": node/npx on this machine come only
  # from mise, which puts them on PATH via its interactive-shell hook. Agents spawn MCP child
  # processes with a reduced environment that doesn't carry that hook (confirmed: codex fails
  # with "No such file or directory (os error 2)" trying to exec bare "npx"), so a PATH-based
  # lookup silently fails there. ${pkgs.nodejs}/bin/npx resolves regardless of PATH, on every
  # host (including work-atdj, which has no mise), without adding node to the interactive PATH
  # (pkgs.nodejs is referenced here only, never added to home.packages, so it can't collide
  # with mise's own node).
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
  # The antigravityReconcile sweep removes every other entry.
  # To add a plugin: declare its source in home.file below AND add its name here.
  antigravityKeepPlugins = [ "playwright" ];

  # Shell case-branches generated from the keep-set used by the reconcile sweep.
  # Each branch matches a plugin basename and skips it (continue).
  antigravityKeepCases = lib.concatMapStringsSep "\n        " (
    p: ''"${p}") continue ;;''
  ) antigravityKeepPlugins;
in

{
  home = {
    file = {
      # Shared instructions -> antigravity's canonical filename.
      ".gemini/antigravity-cli/ANTIGRAVITY.md".source = mkOut "${aiDir}/AGENTS.md";

      # Shared skills dir -> antigravity's skills dir.
      # force = true: existing entries are symlinks (from Ansible), not regular files,
      # so home-manager's backupFileExtension cannot move them aside automatically.
      ".gemini/antigravity-cli/skills" = {
        source = mkOut "${aiDir}/skills";
        force = true;
      };

      # Antigravity plugin dir: one leaf symlink to the linkFarm assembled above.
      ".gemini/antigravity-cli/plugins/playwright" = {
        source = playwrightAntigravityPlugin;
        force = true;
      };

      # settings.json is deliberately NOT declared here - unlike claude/copilot, agy
      # rewrites it at runtime (trustedWorkspaces, permissions), so a plain symlink gets
      # replaced by a real file and home-manager's checkLinkTargets aborts activation
      # trying to back it up. It's merge-reconciled by antigravitySettings below instead,
      # same rationale as modules/home/docker.nix (owns only the keys it declares,
      # merges around the rest).
    };

    activation = {
      # Merge-reconcile antigravity's settings.json instead of symlinking it (see the
      # home.file comment above for why): own only the declared keys, pass through
      # everything agy has written at runtime (trustedWorkspaces, permissions, ...).
      # `. * $_d[0]` is jq's recursive merge with the declared side winning, so
      # enableTelemetry/model here always match home/ai/settings/antigravity.json.
      # Reads the declared file from the live repo checkout (aiDir), not the nix
      # store, matching home/ai/*'s existing edit-without-rebuild behavior where
      # possible - though a rebuild is still needed here to actually apply the merge.
      antigravitySettings = mkReconcile {
        name = "antigravity-settings";
        text = ''
          _decl="${aiDir}/settings/antigravity.json"
          _f="$HOME/.gemini/antigravity-cli/settings.json"
          if [ -e "$_decl" ]; then
            mkdir -p "$(dirname "$_f")"
            [ -e "$_f" ] || printf '{}' > "$_f"
            json_edit "$_f" --slurpfile _d "$_decl" '. * $_d[0]'
          fi
        '';
      };

      # agy self-updates in the background during a session, but the fresh binary only takes
      # effect on the NEXT launch (updater/update_status.json says "restart CLI to use"). That
      # leaves a window where a rebuild-then-launch cycle still runs the previous version. Force
      # the update here so, by the time `rebuild` returns, the on-disk binary is current.
      # `|| true` so a network hiccup does not fail the whole rebuild.
      agyUpdate = mkReconcile {
        name = "agy-update";
        text = ''
          _agy=/opt/homebrew/bin/agy
          if [ -x "$_agy" ]; then
            "$_agy" update || true
          fi
        '';
      };

      # Enforce nix as the single source of truth for antigravity plugins (keep-set:
      # antigravityKeepPlugins above) AND Gemini CLI extensions. Filesystem + JSON reset,
      # not CLI calls - these CLIs are networked or disagree with on-disk state
      # (unreliable offline).
      #
      # The gemini extension removal is the critical step: superpowers and context7 are
      # installed there and auto-imported into antigravity on `agy` startup. Removing only
      # the antigravity copy without removing the gemini source lets them re-appear on the
      # next `agy` launch - so both stores are swept together, in this one place.
      #
      # Safety: every rm is on an explicit quoted path; [ -e ]/[ -d ] guards skip missing
      # files; JSON state files agents also read are rewritten via full-file printf of a
      # constant (atomic enough for these reset-to-empty cases).
      antigravityReconcile = mkReconcile {
        name = "antigravity-reconcile";
        text = ''
          # ── Gemini CLI extensions (root import source for antigravity) ─────────
          # nix declares no gemini extensions; remove all extension dirs and reset enablement.
          _gemini_ext="$HOME/.gemini/extensions"
          if [ -d "$_gemini_ext" ]; then
            for _entry in "$_gemini_ext"/*; do
              [ -e "$_entry" ] || continue
              _name=$(basename "$_entry")
              [ "$_name" = "extension-enablement.json" ] && continue
              rm -rf "$_entry"
            done
            printf '{}' > "$_gemini_ext/extension-enablement.json"
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
                *) rm -rf "$_entry" ;;
              esac
            done
          fi
          # Reset import manifest so agy does not reimport removed plugins.
          _agy_manifest="$HOME/.gemini/antigravity-cli/import_manifest.json"
          if [ -e "$_agy_manifest" ]; then
            printf '{"imports":[]}' > "$_agy_manifest"
          fi

          # Stale backups (.hm-bak and agent-created dated copies):
          # home-manager creates *.hm-bak when replacing a file that already existed;
          # agents create settings.json.YYYYMMDD before overwriting their config.
          # Both recur as long as agents fight the symlinks, so this sweep is
          # permanent (unlike the one-shot first-takeover .hm-baks in legacy.nix).
          # Each agent module sweeps its own config dir. Note the checkLinkTargets
          # gap: a stale settings.json.hm-bak can abort activation BEFORE any
          # activation script runs, which is why rebuild.sh also runs a preflight
          # *.hm-bak sweep - this sweep alone can't reach the file that blocks it.
          find "$HOME/.gemini/antigravity-cli" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
