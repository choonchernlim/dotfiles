# Antigravity (agy): shared-instructions/skills symlinks, playwright plugin,
# herdr hook, settings and hooks merge-reconcile, self-update, and the reconcile
# sweep covering both agy's own plugin store AND ~/.gemini/extensions (Gemini
# CLI) - the root import source agy reimports plugins from on startup.
#
# Global customizations live in ~/.gemini/config/; settings.json stays in
# ~/.gemini/antigravity-cli/ (see docs/gotchas.md).
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

  # See ./default.nix for why this is an absolute nix-store npx.
  playwrightMcp = {
    command = "${pkgs.nodejs}/bin/npx";
    args = [ "@playwright/mcp@0.0.83" ];
  };

  # One directory derivation, linked as a single leaf: home-manager cannot
  # mkdir -p through an existing directory symlink to place per-file entries
  # inside it (force only overrides leaf collisions), and agy's own plugin
  # installs leave such symlinks here. A single leaf + force replaces one.
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

  # Plugin basenames under ~/.gemini/config/plugins/ that the sweep
  # keeps. To add one: declare its source in home.file AND add its name here.
  antigravityKeepPlugins = [ "playwright" ];
  antigravityKeepCases = lib.concatMapStringsSep "\n        " (
    p: ''"${p}") continue ;;''
  ) antigravityKeepPlugins;
in

{
  home = {
    file = {
      ".gemini/config/AGENTS.md".source = mkOut "${aiDir}/AGENTS.md";
      # The `reviewer` subagent named by AGENTS.md's pre-commit review.
      ".gemini/config/agents/reviewer.md".source = mkOut "${aiDir}/agents/antigravity/reviewer.md";
      # agy has no native ~/.agents support, so this links at the hub
      # (./default.nix), not at the repo. force: agy's own config migration
      # leaves a symlink here (into an old home-manager generation), which
      # home-manager's backupFileExtension cannot move aside on its own.
      ".gemini/config/skills" = {
        source = mkOut "${config.home.homeDirectory}/.agents/skills";
        force = true;
      };
      ".gemini/config/plugins/playwright" = {
        source = playwrightAntigravityPlugin;
        force = true;
      };
      # Vendored from `herdr integration install antigravity-cli`; the herdr
      # entry in settings/antigravity-hooks.json points here (see the claude
      # module for why mkOut).
      ".gemini/config/hooks/herdr-agent-state.sh".source =
        mkOut "${aiDir}/hooks/antigravity/herdr-agent-state.sh";
      # settings.json is deliberately NOT a symlink: agy rewrites it at runtime
      # (trustedWorkspaces, permissions), which replaces a symlink with a real
      # file and makes home-manager's checkLinkTargets abort the next rebuild.
      # antigravitySettings below merge-reconciles it instead (same pattern as
      # modules/home/docker.nix).
    };

    activation = {
      # Own only the declared keys, pass through everything agy wrote. `. * $d`
      # is jq's recursive merge with the declared side winning. Reads the
      # declared files from the live checkout; a rebuild still applies them.
      # A literal $HOME in a declared settings string becomes the real home:
      # permission rules take absolute paths only. (Hook commands run via sh -c,
      # so hooks.json keeps "$HOME" for the shell, like claude.json.)
      # permissions.allow and .deny are appended to, not merged: a declared
      # array would replace the rules agy writes at runtime. Neither path can
      # retract a key or rule that is no longer declared.
      antigravitySettings = mkReconcile {
        name = "antigravity-settings";
        text = ''
          _decl="${aiDir}/settings/antigravity.json"
          _f="$HOME/.gemini/antigravity-cli/settings.json"
          if [ -e "$_decl" ]; then
            mkdir -p "$(dirname "$_f")"
            [ -s "$_f" ] || printf '{}' > "$_f"
            json_edit "$_f" --slurpfile _d "$_decl" --arg home "$HOME" '
              ($_d[0] | walk(if type == "string" then gsub("\\$HOME(?![A-Za-z0-9_])"; $home) else . end)) as $d
              | . * ($d | del(.permissions.allow, .permissions.deny))
              | reduce ("allow", "deny") as $k (.;
                  .permissions[$k] = ((.permissions[$k] // []) as $c
                    | $c + (($d.permissions[$k] // []) - $c)))'
          fi
          # hooks.json, which agy's /hooks rewrites: own only the "herdr" group.
          _decl="${aiDir}/settings/antigravity-hooks.json"
          _f="$HOME/.gemini/config/hooks.json"
          if [ -e "$_decl" ]; then
            mkdir -p "$(dirname "$_f")"
            [ -s "$_f" ] || printf '{}' > "$_f"
            json_edit "$_f" --slurpfile _d "$_decl" '. * $_d[0]'
          fi
        '';
      };

      # agy self-updates in the background but only uses the new binary on the
      # next launch; force it here so the on-disk binary is current when
      # `rebuild` returns. (The cask is greedy = false for the same reason.)
      agyUpdate = mkReconcile {
        name = "agy-update";
        text = ''
          _agy=/opt/homebrew/bin/agy
          if [ -x "$_agy" ]; then
            "$_agy" update || true
          fi
        '';
      };

      # Filesystem + JSON reset, not CLI calls (the CLIs are networked and
      # disagree with on-disk state offline). The gemini extension removal is
      # the critical step: extensions installed there are auto-imported into
      # agy on startup, so removing only agy's copy lets them reappear.
      antigravityReconcile = mkReconcile {
        name = "antigravity-reconcile";
        text = ''
          # Gemini CLI extensions: nix declares none - remove all, reset enablement.
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

          # agy plugins: keep-set prune (including *.hm-bak backup dirs).
          _agy_plugins="$HOME/.gemini/config/plugins"
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
          # Reset the import manifest so agy does not reimport removed plugins.
          _agy_manifest="$HOME/.gemini/antigravity-cli/import_manifest.json"
          if [ -e "$_agy_manifest" ]; then
            printf '{"imports":[]}' > "$_agy_manifest"
          fi

          # Stale backups: home-manager's *.hm-bak and the agent's own dated
          # settings.json.YYYYMMDD copies. Permanent sweep. A stale
          # settings.json.hm-bak can abort activation before this ever runs,
          # which is why rebuild.sh also sweeps *.hm-bak up front.
          find "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
