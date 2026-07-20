# Core home config shared by every host: packages, live-symlinked app configs,
# fonts. Feature modules (zsh.nix, mise.nix, gcloud.nix, ai.nix) are selected
# per-host in hosts/*.nix - same pattern as the homebrew bundles.
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
    sessionVariables = {
      EDITOR = "nvim";
      # Ported from the old user-owned ~/.zshrc_conf/env.sh - TERM alone (xterm-256color)
      # doesn't promise 24-bit color, and not every terminal sets this itself.
      COLORTERM = "truecolor";
    };
    # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
    file = {
      ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
      ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
      ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
    };

    # Retires setups the final Ansible migration dropped rather than ported;
    # converges any drifted machine on every rebuild.
    activation.legacyReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # amix/vimrc distro dropped - Neovim (live-symlinked config) is the editor.
      [ -d "$HOME/.vim_runtime" ] && rm -rf "$HOME/.vim_runtime" || true
      rm -f "$HOME/.vimrc" || true

      # COLORTERM now set via sessionVariables above - drop the old user-owned snippet.
      rm -f "$HOME/.zshrc_conf/env.sh" || true

      # Ansible python role's packages: requests served only vimrc's updater,
      # crcmod only the deprecated gsutil rsync. Its install mechanism was
      # ambiguous (pip vs brew), so both removals are attempted, all guarded.
      /usr/bin/python3 -m pip uninstall -y requests crcmod >/dev/null 2>&1 || true
      _brew=/opt/homebrew/bin/brew
      if [ -x "$_brew" ]; then
        for _pkg in requests crcmod; do
          "$_brew" list --formula "$_pkg" >/dev/null 2>&1 && \
            "$_brew" uninstall "$_pkg" || true
        done
      fi
    '';
  };
  fonts.fontconfig.enable = true;
}
