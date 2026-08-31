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
      #    repo's grill-me skill in home/ai/skills/ ──────────────────────────
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
}
