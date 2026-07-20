# Shell feature module: zsh (native autosuggestions/highlighting), starship
# prompt, direnv. Selected per-host via hosts/*.nix home imports.
{
  config,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home = {
    # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
    file.".config/starship.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/starship.toml";

    # Cleanup from the Ansible ohmyzsh role port, kept as a permanent reconcile
    # so a drifted machine converges with `rebuild` alone (aiReconcile pattern).
    # Removes ONLY named files - ~/.zshrc_conf also holds user- and work-owned
    # snippets (alias-custom.sh, ...) that must survive. zscaler.sh used to live
    # here but is now nix-managed (home/zscaler.nix, work/work-atdj only), which
    # sweeps it via its own zscalerReconcile if it reappears.
    activation.zshReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # User/work-owned snippets live here; the dir must exist for the zshrc
      # sourcing loop on a fresh machine.
      mkdir -p "$HOME/.zshrc_conf" || true

      # oh-my-zsh replaced by native home-manager plugins + starship.
      rm -f "$HOME/.zshrc_conf/ohmyzsh.sh" "$HOME/.zshrc_conf/alias.sh" || true
      rm -f "$HOME/.p10k.zsh" || true
      [ -d "$HOME/.oh-my-zsh" ] && rm -rf "$HOME/.oh-my-zsh" || true

      # home-manager backs up a pre-existing starship config as .hm-bak when it
      # first takes over the path; aiReconcile's sweep only covers agent dirs.
      rm -f "$HOME/.config/starship.toml.hm-bak" || true

      # Host/version-suffixed compdumps were written by the system-level
      # compinit in /etc/zshrc (now disabled); only ~/.zcompdump (used by
      # home-manager's cached compinit) is legitimate.
      rm -f "$HOME"/.zcompdump-* || true

      # Delisted brews now provided by nixpkgs; cleanup="none" never
      # uninstalls, so reconcile does. No-op once converged.
      _brew=/opt/homebrew/bin/brew
      if [ -x "$_brew" ]; then
        for _pkg in zsh-autosuggestions zsh-syntax-highlighting starship direnv; do
          "$_brew" list --formula "$_pkg" >/dev/null 2>&1 && \
            "$_brew" uninstall "$_pkg" || true
        done
      fi

      # Resolve nix-homebrew's patched-brew completions dir once per rebuild
      # (globbing /nix/store costs ~200ms - too slow for every shell startup;
      # zshrc reads this cache file instead).
      mkdir -p "$HOME/.cache/zsh" || true
      for _d in /nix/store/*brew*patched/completions/zsh; do
        if [ -d "$_d" ]; then
          printf '%s' "$_d" > "$HOME/.cache/zsh/brew-zsh-completions" || true
          break
        fi
      done
    '';
  };

  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      # Trust the completion dump unless it is older than a day: compinit's full
      # compaudit costs hundreds of ms per shell; -C skips it.
      completionInit = ''
        autoload -U compinit
        if [[ -n $HOME/.zcompdump(#qN.mh+24) ]]; then
          compinit
        else
          compinit -C
        fi
      '';
      initContent = lib.mkMerge [
        (lib.mkOrder 550 ''
          # Add brew completions (nix store path) before compinit. The path is
          # resolved at rebuild time by zshReconcile into a cache file - globbing
          # /nix/store here would cost ~200ms on every shell.
          if [[ -r ~/.cache/zsh/brew-zsh-completions ]]; then
            _d="$(<~/.cache/zsh/brew-zsh-completions)"
            [[ -d $_d ]] && fpath=("$_d" $fpath)
            unset _d
          fi
        '')
        ''
          bindkey '^f' autosuggest-accept
          # Case-insensitive completion (behavior previously provided by oh-my-zsh).
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
          # Source user/work-owned shell snippets (alias-custom, ...) - not
          # managed by nix. All Ansible-written snippets have been ported.
          for f in ~/.zshrc_conf/*.sh; do
            [ -r "$f" ] && source "$f"
          done
        ''
      ];
      shellAliases = {
        rebuild = "~/.dotfiles/rebuild.sh";
        personal_claude = "ANTHROPIC_BASE_URL= ANTHROPIC_AUTH_TOKEN= claude"; # Bypass LiteLLM to use personal Claude account directly.
      };
    };

    # Prompt. Config deliberately not in `settings` - it lives in
    # home/.config/starship.toml (live-symlinked) so look-and-feel tweaks
    # take effect on the next prompt without a rebuild.
    starship = {
      enable = true;
      enableZshIntegration = true;
    };

    # Replaces the oh-my-zsh direnv plugin; nix-direnv adds nix-shell caching.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
