# TEMPORARY - local patch to Claude's Langfuse observability plugin (installed
# by claudePlugins in ./default.nix) adding CC_LANGFUSE_TAGS support that
# upstream 1.0.0 lacks (its get_trace_tags() only returns ["claude-code"] +
# skill:<name> tags).
#
# Delete this file once the plugin fork/upstream ships CC_LANGFUSE_TAGS; only
# the marketplace URL in settings/claude.json would change, the `claude` alias
# in ./default.nix stays. Imported by ./default.nix.
{
  lib,
  pkgs,
  ...
}:

let
  mkReconcile = import ../../lib/reconcile.nix { inherit pkgs lib; };

  # Inserted just before the `if __name__ == "__main__":` guard (the module
  # calls main() at EOF, so appending after it would never run). Rebinds the
  # module-global get_trace_tags, which the call site looks up by name, so the
  # patch is a pure insertion - no upstream line is touched.
  claudeTagsPatch = pkgs.writeText "claude-langfuse-cc-tags-patch.py" ''
    # --- nix-managed: CC_LANGFUSE_TAGS support (dotfiles modules/home/ai/claude/langfuse.nix) ---
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
  home.activation = {
    # Patch the installed hook. Guarded by grep so a rebuild never inserts a
    # second copy; the guard also matches any build that already reads
    # CC_LANGFUSE_TAGS (a fork, or upstream once it ships), so pointing the
    # marketplace at one never stacks a second wrapper. Globs every version
    # dir so a plugin upgrade is re-patched without an edit here.
    claudeLangfuseTagsPatch = mkReconcile {
      name = "claude-langfuse-tags-patch";
      after = [ "claudePlugins" ];
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
  };
}
