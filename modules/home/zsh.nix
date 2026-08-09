# Shell feature module: zsh (native autosuggestions/highlighting), starship
# prompt, direnv. Selected per-host via hosts/*.nix home imports.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in

{
  home = {
    # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
    file.".config/starship.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/starship.toml";

    # Permanent per-rebuild setup. (Ansible-era ohmyzsh/nvm cleanup moved to
    # legacy.nix; retired brews are removed by cleanup = "zap".)
    activation.zshSetup = mkReconcile {
      name = "zsh-setup";
      text = ''
        # User/work-owned snippets (alias-custom.sh, ...) live here; the dir
        # must exist for the zshrc sourcing loop on a fresh machine.
        mkdir -p "$HOME/.zshrc_conf"

        # Resolve nix-homebrew's patched-brew completions dir once per rebuild
        # (globbing /nix/store costs ~200ms - too slow for every shell startup;
        # zshrc reads this cache file instead). Resolved via the live
        # /opt/homebrew/Library/Homebrew symlink, which nix-homebrew points at
        # the CURRENT patched-brew generation - a bare /nix/store glob could
        # pick a stale generation that GC later deletes.
        mkdir -p "$HOME/.cache/zsh"
        _hb_lib=$(readlink -f /opt/homebrew/Library/Homebrew 2>/dev/null) || _hb_lib=""
        _comp_dir="''${_hb_lib%/Library/Homebrew}/completions/zsh"
        if [ -d "$_comp_dir" ]; then
          printf '%s' "$_comp_dir" > "$HOME/.cache/zsh/brew-zsh-completions"
        fi
      '';
    };
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
          # resolved at rebuild time by zshSetup into a cache file - globbing
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
