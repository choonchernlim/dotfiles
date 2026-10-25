# Core home config every host gets: packages, live-symlinked app configs,
# fonts. Feature modules are selected per-host in hosts/*.nix.
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
  # One-time migration sweeps; delete the file once every host has converged
  # (see the header in legacy.nix).
  imports = [ ./legacy.nix ];

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
      nixfmt # RFC-style formatter (nixpkgs 26.05 renamed nixfmt-rfc-style -> nixfmt)
      statix # nix anti-pattern lint
      deadnix # nix dead-code lint
      # the font everything renders in
      nerd-fonts.hack
    ];
    sessionVariables = {
      EDITOR = "nvim";
      # TERM alone (xterm-256color) doesn't promise 24-bit color, and not every
      # terminal sets this itself.
      COLORTERM = "truecolor";
    };
    # Edit-in-place: the real file stays in the repo, ~/.config just points at it.
    file = {
      ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
      ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
      ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
    };
  };
  fonts.fontconfig.enable = true;
}
