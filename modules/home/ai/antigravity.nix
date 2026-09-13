# Antigravity (agy): shared-instructions/skills symlinks, playwright plugin,
# settings merge-reconcile, self-update, and the reconcile sweep covering both
# agy's own plugin store AND ~/.gemini/extensions (Gemini CLI) - the root
# import source agy reimports plugins from on startup.
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
    args = [ "@playwright/mcp@latest" ];
  };

  # One directory derivation, linked as a single leaf: plugins/playwright was
  # already a directory symlink pre-nix, and home-manager cannot mkdir -p
  # through a symlink to place per-file entries inside it (force only overrides
  # leaf collisions). A single leaf + force handles that case.
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

  # Plugin basenames under ~/.gemini/antigravity-cli/plugins/ that the sweep
  # keeps. To add one: declare its source in home.file AND add its name here.
  antigravityKeepPlugins = [ "playwright" ];
  antigravityKeepCases = lib.concatMapStringsSep "\n        " (
    p: ''"${p}") continue ;;''
  ) antigravityKeepPlugins;
in

{
  home = {
    file = {
      ".gemini/antigravity-cli/ANTIGRAVITY.md".source = mkOut "${aiDir}/AGENTS.md";
      # agy reads global skills from ~/.gemini/antigravity-cli/skills only (no
      # native ~/.agents support), so this links at the hub (./default.nix),
      # not at the repo. force: pre-nix entries here were symlinks, which
      # home-manager's backupFileExtension cannot move aside on its own.
      ".gemini/antigravity-cli/skills" = {
        source = mkOut "${config.home.homeDirectory}/.agents/skills";
        force = true;
      };
      ".gemini/antigravity-cli/plugins/playwright" = {
        source = playwrightAntigravityPlugin;
        force = true;
      };
      # settings.json is deliberately NOT a symlink: agy rewrites it at runtime
      # (trustedWorkspaces, permissions), which replaces a symlink with a real
      # file and makes home-manager's checkLinkTargets abort the next rebuild.
      # antigravitySettings below merge-reconciles it instead (same pattern as
      # modules/home/docker.nix).
    };

    activation = {
      # Own only the declared keys, pass through everything agy wrote. `. * $d`
      # is jq's recursive merge with the declared side winning. Reads the
      # declared file from the live checkout; a rebuild still applies it.
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
          # Reset the import manifest so agy does not reimport removed plugins.
          _agy_manifest="$HOME/.gemini/antigravity-cli/import_manifest.json"
          if [ -e "$_agy_manifest" ]; then
            printf '{"imports":[]}' > "$_agy_manifest"
          fi

          # Stale backups: home-manager's *.hm-bak and the agent's own dated
          # settings.json.YYYYMMDD copies. Permanent sweep. A stale
          # settings.json.hm-bak can abort activation before this ever runs,
          # which is why rebuild.sh also sweeps *.hm-bak up front.
          find "$HOME/.gemini/antigravity-cli" -maxdepth 1 \
            \( -name '*.hm-bak' -o -name 'settings.json.2[0-9][0-9][0-9]*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        '';
      };
    };
  };
}
