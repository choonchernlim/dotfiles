# One-time migration sweeps - DELETE THIS FILE once every host (work, personal,
# work-atdj) has run one rebuild that includes it; nothing here re-creates state.
#
# This module collects every temporal cleanup that used to be scattered through
# the feature modules (default.nix, zsh.nix, mise.nix, gcloud.nix, zscaler.nix,
# ai/, gitea.nix, langfuse.nix), so retiring the whole migration era later is
# a one-file deletion instead of an archaeology dig. Feature modules now carry
# only PERMANENT reconciliation (state that can drift back on a converged
# machine). Imported unconditionally from modules/home/default.nix - every line
# is a guarded no-op on a machine that never had the artifact.
#
# NOT swept here (deliberately): retired homebrew formulae/casks. Since the
# zap flip, `homebrew.onActivation.cleanup = "zap"` removes every undeclared
# brew/cask on each switch - per-package uninstall loops would be dead code.
{ pkgs, lib, ... }:

let
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in

{
  home.activation.legacySweep = mkReconcile {
    name = "legacy-sweep";
    text = ''
      # ── Ansible vim role (amix/vimrc distro) - Neovim is the editor ─────────
      rm -rf "$HOME/.vim_runtime"
      rm -f "$HOME/.vimrc"

      # ── Superseded ~/.zshrc_conf snippets (each replaced by a nix module) ───
      rm -f "$HOME/.zshrc_conf/env.sh"      # COLORTERM -> home/default.nix sessionVariables
      rm -f "$HOME/.zshrc_conf/ohmyzsh.sh"  # oh-my-zsh -> home/zsh.nix (hm plugins + starship)
      rm -f "$HOME/.zshrc_conf/alias.sh"    # ohmyzsh-era aliases, ported
      rm -f "$HOME/.zshrc_conf/nvm.sh"      # nvm -> home/mise.nix
      rm -f "$HOME/.zshrc_conf/sdkman.sh"   # sdkman -> home/mise.nix (Java 25)
      rm -f "$HOME/.zshrc_conf/tfenv.sh"    # tfenv -> home/mise.nix
      rm -f "$HOME/.zshrc_conf/gcloud.sh"   # gcloud wiring -> home/gcloud.nix
      rm -f "$HOME/.zshrc_conf/zscaler.sh"  # zscaler wiring -> home/zscaler.nix

      # ── Retired shell/prompt/tool-manager state dirs ────────────────────────
      rm -rf "$HOME/.oh-my-zsh"
      rm -f "$HOME/.p10k.zsh"
      rm -rf "$HOME/.sdkman"
      rm -rf "$HOME/.nvm"

      # ── Host/version-suffixed compdumps from the (now disabled) /etc/zshrc
      #    system compinit; only ~/.zcompdump (hm's cached compinit) is used ───
      rm -f "$HOME"/.zcompdump-*

      # ── Ansible python role packages: requests served only vimrc's updater,
      #    crcmod only the deprecated gsutil rsync (brew copies zap-swept) ─────
      /usr/bin/python3 -m pip uninstall -y requests crcmod >/dev/null 2>&1 || true

      # ── rtk (retired 2026-08-07): command rewriting removed from all agents.
      #    Covers drift, .hm-bak residue, and anything a stray `rtk init`
      #    re-created; the state dir was never nix-owned ─────────────────────
      rm -f "$HOME/.copilot/hooks/rtk-rewrite.json" \
            "$HOME/.copilot/hooks/rtk-rewrite.json.hm-bak"
      rm -f "$HOME/.config/opencode/plugins/rtk.ts" \
            "$HOME/.config/opencode/plugins/rtk.ts.hm-bak"
      rm -rf "$HOME/Library/Application Support/rtk"

      # ── Gemini CLI (retired 2026-08-30): antigravity (agy) replaced it; the
      #    google-gemini cask (work/personal) is the separate Gemini desktop app
      #    and stays. Sweeps only CLI-owned state under ~/.gemini - NOT
      #    antigravity-cli/ (agy's own home), extensions/ (kept + reset by
      #    antigravityReconcile in ai/antigravity.nix), or config/, users/,
      #    tasks/ (still actively written, by agy or the desktop app, as of the
      #    retirement date). skills/ held only "forge", the predecessor of the
      #    grill-me skill, which now lives in the skills repo ───────────────
      rm -f "$HOME/.gemini/GEMINI.md" \
            "$HOME/.gemini/settings.json" \
            "$HOME/.gemini/settings.json.sample" \
            "$HOME/.gemini/google_accounts.json" \
            "$HOME/.gemini/installation_id" \
            "$HOME/.gemini/oauth_creds.json" \
            "$HOME/.gemini/projects.json" \
            "$HOME/.gemini/state.json" \
            "$HOME/.gemini/trustedFolders.json"
      rm -rf "$HOME/.gemini/history" \
             "$HOME/.gemini/tmp" \
             "$HOME/.gemini/skills"

      # ── Codex per-skill links (2026-09-13, lived one rebuild): the whole-dir
      #    ~/.codex/skills symlink from before them is invisible to home-manager's
      #    cleanup - the path became a directory in the next generation, so
      #    cleanOldGen skipped it, and it is not in the previous generation any
      #    more. While it exists, everything Codex writes under ~/.codex/skills/
      #    lands inside the git checkout. -L guard: a real dir Codex created
      #    itself is never touched ──────────────────────────────────────────────
      if [ -L "$HOME/.codex/skills" ]; then
        rm -f "$HOME/.codex/skills"
      fi

      # ── First-takeover .hm-bak backups: created once when home-manager first
      #    claimed a path that already existed (pre-nix machines) ──────────────
      rm -f "$HOME/.config/starship.toml.hm-bak"
      rm -f "$HOME/.config/mise/config.toml.hm-bak"
      rm -f "$HOME/.config/gitea/docker-compose.yml.hm-bak"
      rm -rf "$HOME/.config/gitea.hm-bak"
      rm -f "$HOME/.config/langfuse/docker-compose.yml.hm-bak"
      rm -rf "$HOME/.config/langfuse.hm-bak"
    '';
  };

  # ── Dev root move (2026-10-14): ~/Documents/development -> ~/Developer ──────
  # ~/Documents is TCC-protected, so a detached process (the herdr server) is
  # denied every path that resolves into it, including the live-symlinked
  # configs. The user does the `mv` by hand on each host; this rewrites the
  # path-keyed state the move leaves stale. It acts only once the old root is
  # gone, so it never runs half-way through the move, and every step is a no-op
  # once its old paths are gone. App-owned state (herdr session.json, which the
  # running server overwrites; IDE recent projects) is deliberately left alone.
  # Retiring this block also drops ~/Documents/development from the mise
  # trusted_config_paths.
  home.activation.devRootMigration = mkReconcile {
    name = "dev-root-migration";
    path = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.direnv
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      _old="$HOME/Documents/development"
      _new="$HOME/Developer"
      _tilde='~'
      _old_tilde="$_tilde/Documents/development"
      _new_tilde="$_tilde/Developer"

      if [ -e "$_old" ]; then
        if [ -d "$_new" ]; then
          echo "dev-root: warning: both $_old_tilde and $_new_tilde exist - finish the move by hand, then rebuild" >&2
        else
          echo "dev-root: warning: move pending - see docs/gotchas.md (dev root move)" >&2
        fi
        exit 0
      fi
      if [ ! -d "$_new" ]; then
        exit 0
      fi
      # Without Documents access the old root only *looks* absent.
      if ! ls "$HOME/Documents" >/dev/null 2>&1; then
        echo "dev-root: warning: no access to ~/Documents - rebuild from a terminal app to migrate" >&2
        exit 0
      fi

      # sed -E rewrites for both spellings of the old root. A match must end at
      # a path boundary, so ~/Documents/development-x is never rewritten.
      _re() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
      _end='([/"'"'"'[:space:]:]|$)'
      _sed_abs="s#$(_re "$_old")$_end#$_new\\1#g"
      _sed_tilde="s#$(_re "$_old_tilde")$_end#$_new_tilde\\1#g"

      # jq: rewrite a string rooted at $old to $new.
      _jq_mv='def mv: if type == "string" and (. == $old or startswith($old + "/"))
                     then $new + .[($old | length):] else . end;'

      # Cheap pre-check, so a migrated machine never re-runs a rewriter.
      _has() { [ -f "$1" ] && grep -qF -- "$2" "$1"; }

      # _apply FILE CMD...: run CMD with FILE as its last argument and replace
      # FILE with the output (keeping its mode) when CMD succeeded and the
      # output is non-empty and different. Returns 0 only when FILE changed,
      # so only real rewrites are reported.
      _apply() {
        _file="$1"
        shift
        _tmp=$(mktemp "$_file.XXXXXX") || return 1
        if "$@" "$_file" > "$_tmp" && [ -s "$_tmp" ] && ! cmp -s "$_file" "$_tmp" \
          && chmod --reference="$_file" "$_tmp"; then
          mv "$_tmp" "$_file"
        else
          rm -f "$_tmp"
          return 1
        fi
      }

      _rewrite_text() { _apply "$1" sed -E -e "$_sed_abs" -e "$_sed_tilde"; }

      # git: includeIf gitdir: conditions and their include paths. A stale
      # condition silently drops the per-folder identity from every commit.
      if _has "$HOME/.gitconfig" /Documents/development && _rewrite_text "$HOME/.gitconfig"; then
        echo "dev-root: rewrote $HOME/.gitconfig" >&2
      fi

      # Claude Code: path-keyed projects (trust, allowed tools) and repo
      # lookups. When both keys exist the new one wins - it is the live one.
      if _has "$HOME/.claude.json" "\"$_old" && _apply "$HOME/.claude.json" \
        jq --arg old "$_old" --arg new "$_new" "$_jq_mv"'
          def mvkeys: reduce to_entries[] as $e ({};
            ($e.key | mv) as $k
            | if $k != $e.key and has($k) then . else .[$k] = $e.value end);
          walk(if type == "object" then mvkeys | map_values(mv)
               elif type == "array" then map(mv) else . end)'; then
        echo "dev-root: rewrote $HOME/.claude.json" >&2
      fi
      # Prompt history (JSON Lines, one record per prompt).
      _hist="$HOME/.claude/history.jsonl"
      if _has "$_hist" "\"project\":\"$_old" && _apply "$_hist" \
        jq -c --arg old "$_old" --arg new "$_new" "$_jq_mv"' if has("project") then .project |= mv else . end'; then
        echo "dev-root: rewrote $_hist" >&2
      fi
      # Per-project memory and sessions: the folder name is the project path
      # with every non-alphanumeric character replaced by "-". That encoding
      # is lossy (~/Documents/development-x encodes like a child of the old
      # root), so a folder whose sessions record a cwd outside the old root is
      # skipped.
      _proj="$HOME/.claude/projects"
      _enc_old="''${_old//[^A-Za-z0-9]/-}"
      _enc_new="''${_new//[^A-Za-z0-9]/-}"
      for _d in "$_proj/$_enc_old" "$_proj/$_enc_old"-*; do
        [ -d "$_d" ] || continue
        _cwd=$(grep -h -m 1 -o '"cwd":"[^"]*"' "$_d"/*.jsonl 2>/dev/null | head -n 1 || true)
        _cwd="''${_cwd#\"cwd\":\"}"
        case "''${_cwd%\"}" in "" | "$_old" | "$_old"/*) ;; *) continue ;; esac
        _to="$_proj/$_enc_new''${_d#"$_proj/$_enc_old"}"
        if [ -e "$_to" ]; then
          echo "dev-root: warning: both $_d and $_to exist - merge them by hand" >&2
        else
          mv "$_d" "$_to"
          echo "dev-root: moved $_d" >&2
        fi
      done

      # Codex: [projects."<path>"] trust and other path-keyed tables. A renamed
      # table or key that already exists is dropped instead, since TOML rejects
      # duplicates and the existing one is the live one. The file is read twice:
      # pass 1 records existing tables and keys, pass 2 rewrites.
      _codex="$HOME/.codex/config.toml"
      if _has "$_codex" "\"$_old" && _apply "$_codex" awk -v old="$_old" -v new="$_new" '
          function mv(s,   out, i, c) {
            out = ""
            while ((i = index(s, "\"" old)) > 0) {
              c = substr(s, i + 1 + length(old), 1)
              if (c != "/" && c != "\"") { out = out substr(s, 1, i); s = substr(s, i + 1); continue }
              out = out substr(s, 1, i) new
              s = substr(s, i + 1 + length(old))
            }
            return out s
          }
          function key(s) { sub(/[ \t]*=.*/, "", s); return s }
          FNR == 1 { table = "" }
          NR == FNR {
            if ($0 ~ /^\[/) { table = $0; seen[table] = 1 }
            else if ($0 ~ /=/) seen[table SUBSEP key($0)] = 1
            next
          }
          /^\[/ {
            table = mv($0); skip = (table != $0 && (table in seen))
            if (!skip) print table
            next
          }
          skip { next }
          {
            line = mv($0)
            if (key(line) != key($0) && line ~ /=/ && ((table SUBSEP key(line)) in seen)) next
            print line
          }
        ' "$_codex"; then
        echo "dev-root: rewrote $_codex" >&2
      fi

      # git worktrees: each one's .git file and its repo's gitdir back-link hold
      # absolute paths. Fix the back-links that moved, then `repair` rewrites
      # the worktree side. /usr/bin/git: the activation PATH is hermetic, and
      # this is the git the user's checkouts are made with.
      if [ -x /usr/bin/git ]; then
        for _git_dir in "$_new"/*/.git "$_new"/*/*/.git "$_new"/*/*/*/.git; do
          [ -d "$_git_dir/worktrees" ] || continue
          _wts=()
          for _link in "$_git_dir"/worktrees/*/gitdir; do
            [ -f "$_link" ] || continue
            if _has "$_link" "$_old"; then
              _rewrite_text "$_link" || true
            fi
            read -r _wt < "$_link" || true
            _wt="''${_wt%/*}"
            if _has "$_wt/.git" "$_old"; then
              _wts+=("$_wt")
            fi
          done
          _repo="''${_git_dir%/.git}"
          if [ "''${#_wts[@]}" -gt 0 ] && /usr/bin/git -C "$_repo" worktree repair "''${_wts[@]}" >/dev/null 2>&1; then
            echo "dev-root: repaired ''${#_wts[@]} worktree(s) of $_repo" >&2
          fi
        done
      fi
      # herdr worktrees of repos nested deeper than the globs above: their
      # back-links point into ~/.herdr (unchanged), so only the worktree's own
      # .git file needs the new repo path.
      for _wt_git in "$HOME/.herdr/worktrees"/*/*/.git; do
        if _has "$_wt_git" "$_old" && _rewrite_text "$_wt_git"; then
          echo "dev-root: rewrote $_wt_git" >&2
        fi
      done

      # direnv: an approval is named sha256(path + "\n" + content). Re-allow at
      # the new path only when the old approval still matches the current
      # content, so an .envrc edited since it was approved stays blocked.
      _allow="''${XDG_DATA_HOME:-$HOME/.local/share}/direnv/allow"
      for _a in "$_allow"/*; do
        [ -f "$_a" ] || continue
        read -r _p < "$_a" || true
        case "$_p" in "$_old"/*) ;; *) continue ;; esac
        _np="$_new''${_p#"$_old"}"
        [ -f "$_np" ] || continue
        _h=$({ printf '%s\n' "$_p"; cat "$_np"; } | sha256sum | cut -d ' ' -f 1)
        if [ "$_h" = "''${_a##*/}" ] && direnv allow "$_np"; then
          rm -f "$_a"
          echo "dev-root: re-allowed $_np" >&2
        fi
      done
    '';
  };
}
