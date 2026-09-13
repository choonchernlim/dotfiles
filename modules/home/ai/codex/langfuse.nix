# TEMPORARY - Codex's Langfuse "tracing" plugin: install + enable if absent.
# Delete this file when Langfuse tracing for Codex is retired; the `codex`
# alias in ./default.nix is harmless without it. Imported by ./default.nix.
{
  lib,
  pkgs,
  ...
}:

let
  mkReconcile = import ../../lib/reconcile.nix { inherit pkgs lib; };
in

{
  # Runs after codexConfig: that upsert only rewrites the config.toml preamble,
  # and this only appends tables at EOF, so the two writes never race.
  #
  # Two idempotent, best-effort guards:
  #   (a) install-if-absent via `codex plugin add` (grep of `plugin list --json`
  #       rather than a jq schema). Same HTTPS-URL + /usr/bin/git reasoning as
  #       claude/langfuse.nix: the owner/repo shorthand resolves to an SSH clone
  #       and the hermetic PATH has no ssh; the nix git trusts only the Zscaler
  #       cert via http.sslcainfo.
  #   (b) enable-if-absent fallback: `plugin add` already writes the
  #       [plugins."..."] enabled = true table itself, so this is a no-op in the
  #       common case and only guards a future codex that stops doing so.
  #       [features] is gated separately so an existing table is never duplicated.
  home.activation.codexLangfusePlugin = mkReconcile {
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
}
