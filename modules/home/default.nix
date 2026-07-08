{
  config,
  pkgs,
  lib,
  user,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  imports = [ ./ai.nix ];
  home = {
    username = user;
    homeDirectory = "/Users/${user}";
    stateVersion = "24.11";
    packages = with pkgs; [
      # cli i use constantly
      ripgrep # fast search
      fd # fast find
      fzf # fuzzy finder
      jq # json on the command line
      lazygit
      neovim
      # nix toolchain - formatter + linters (also needed by the Claude repo hook)
      nixfmt # RFC-style formatter; nixpkgs 26.05 renamed nixfmt-rfc-style -> nixfmt (treefmt-nix exposes it as programs.nixfmt)
      statix # nix anti-pattern lint
      deadnix # nix dead-code lint
      # the font everything renders in
      nerd-fonts.hack
    ];
    sessionVariables.EDITOR = "nvim";
    # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
    file = {
      ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
      ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
      ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
    };
  };
  fonts.fontconfig.enable = true;

  programs.zsh = {
    enable = true;
    autosuggestion.enable = false; # disabled: oh-my-zsh (via ~/.zshrc_conf) already provides this
    syntaxHighlighting.enable = false; # disabled: oh-my-zsh (via ~/.zshrc_conf) already provides this
    initContent = lib.mkMerge [
      (lib.mkOrder 550 ''
        # Add brew completions from nix-homebrew's nix store package before compinit.
        # The glob survives brew upgrades - the nix store hash changes each build.
        for _d in /nix/store/*brew*patched/completions/zsh(/N); do
          fpath=("$_d" $fpath)
          break
        done
        unset _d
      '')
      ''
        bindkey '^f' autosuggest-accept
        # Source Ansible-managed shell snippets (oh-my-zsh, p10k, nvm, sdkman, gcloud, aliases, ai env).
        for f in ~/.zshrc_conf/*.sh; do
          [ -r "$f" ] && source "$f"
        done
      ''
    ];
    shellAliases = {
      rebuild = "~/.dotfiles/rebuild.sh";
      personal_claude = "ANTHROPIC_BASE_URL= ANTHROPIC_AUTH_TOKEN= claude"; # Bypass LiteLLM to use personal Claude account directly.
    };
    # Additional aliases commented out for now - revisit once migrated off Ansible.
    # shellAliases = {
    #   ".." = "cd ..";
    #   add = "git add .";
    #   push = "git push";
    #   pull = "git pull";
    #   m = "git switch main";
    #   cc = "claude --dangerously-skip-permissions";  # WARNING: bypasses all permission checks
    #   co = "codex --full-auto";                       # WARNING: fully autonomous, no confirmation
    # };
  };

  # programs.starship commented out - Ansible manages p10k as the active prompt.
  # programs.starship = {
  #   enable = true;
  #   settings = {
  #     add_newline = false;
  #     format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
  #     character = {
  #       success_symbol = "[❯](purple)";
  #       error_symbol = "[❯](red)";
  #     };
  #     cmd_duration.format = "[$duration]($style) ";
  #   };
  # };
}
