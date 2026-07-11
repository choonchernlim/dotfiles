# Core home config shared by every host: packages, live-symlinked app configs,
# fonts. Feature modules (zsh.nix, mise.nix, gcloud.nix, ai.nix) are selected
# per-host in hosts/*.nix - same pattern as the homebrew bundles.
{
  config,
  pkgs,
  user,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
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
}
