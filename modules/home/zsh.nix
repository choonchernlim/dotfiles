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
    # Edit-in-place: the real file stays in the repo, ~/.config just points at it.
    file.".config/starship.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/starship.toml";

    activation.zshSetup = mkReconcile {
      name = "zsh-setup";
      text = ''
        # User-owned snippets (alias-custom.sh, ...) live here; the dir must
        # exist for the zshrc sourcing loop on a fresh machine.
        mkdir -p "$HOME/.zshrc_conf"

        # Resolve nix-homebrew's patched-brew completions dir once per rebuild
        # (globbing /nix/store costs ~200ms - too slow for every shell startup;
        # zshrc reads this cache file instead). Resolved via the live
        # /opt/homebrew/Library/Homebrew symlink, which always points at the
        # CURRENT patched-brew generation, so GC can't leave it dangling.
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
      # Trust the completion dump unless it is older than a day: a full compinit
      # (with compaudit) costs hundreds of ms per shell; -C skips it. The (#q...)
      # glob qualifier only works under extended_glob, hence the anonymous
      # function with a local setopt - without it the test is always true and
      # the fast path never runs.
      completionInit = ''
        autoload -U compinit
        () {
          setopt local_options extended_glob
          if [[ -n $HOME/.zcompdump(#qN.mh+24) ]]; then
            compinit
          else
            compinit -C
          fi
        }
      '';
      initContent = lib.mkMerge [
        (lib.mkOrder 550 ''
          # Add brew completions (nix store path) before compinit; the path is
          # resolved at rebuild time by zshSetup into a cache file.
          if [[ -r ~/.cache/zsh/brew-zsh-completions ]]; then
            _d="$(<~/.cache/zsh/brew-zsh-completions)"
            [[ -d $_d ]] && fpath=("$_d" $fpath)
            unset _d
          fi
        '')
        ''
          bindkey '^f' autosuggest-accept
          # Case-insensitive completion.
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
          # Source user-owned shell snippets (alias-custom, ...) - not managed by nix.
          for f in ~/.zshrc_conf/*.sh; do
            [ -r "$f" ] && source "$f"
          done
        ''
      ];
      shellAliases = {
        rebuild = "~/.dotfiles/rebuild.sh";
        personal_claude = "ANTHROPIC_BASE_URL= ANTHROPIC_AUTH_TOKEN= claude"; # bypass LiteLLM, use the personal Claude account
      };
    };

    # Prompt. Config lives in home/.config/starship.toml (live-symlinked) so
    # look-and-feel tweaks take effect on the next prompt without a rebuild.
    starship = {
      enable = true;
      enableZshIntegration = true;
    };

    # nix-direnv adds nix-shell caching and a persistent GC root per repo.
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
