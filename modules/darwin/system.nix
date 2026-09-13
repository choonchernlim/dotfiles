# macOS system basics shared by every host.
{ user, profile, ... }:

{
  # Determinate manages the Nix daemon, so nix-darwin must not.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  # nixpkgs.hostPlatform is set per-host in hosts/*.nix.

  security.pam.services.sudo_local.touchIdAuth = true;

  # Records which profile this machine runs. rebuild.sh reads it to default the
  # profile argument and to refuse a different one without --force: with
  # homebrew cleanup = "zap", the wrong profile actively uninstalls packages.
  environment.etc."dotfiles-profile".text = "${profile}\n";

  system = {
    primaryUser = user;
    stateVersion = 6;

    # Rosetta 2 so Apple Silicon runs Intel binaries. Functional test, so it is
    # a no-op once installed.
    activationScripts.extraActivation.text = ''
      if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license || true
      fi
    '';

    # macOS UI defaults: deliberately empty, to be designed in its own task.
    defaults = {
      # NSGlobalDomain = {
      #   AppleInterfaceStyle = "Dark";
      #   KeyRepeat = 2;          # fast key repeat
      #   InitialKeyRepeat = 15;  # short delay before repeat
      #   _HIHideMenuBar = true;  # auto-hide the menu bar
      #   AppleShowAllExtensions = true;
      # };
      # dock.autohide = true;
      # finder.FXPreferredViewStyle = "Nlsv";  # list view by default
      # finder.CreateDesktop = false;          # clean desktop
      # trackpad.Clicking = true;              # tap to click
    };
  };

  users.users.${user}.home = "/Users/${user}";

  # home-manager owns zsh completion init (cached compinit) and starship owns
  # the prompt. The nix-darwin defaults would add a second, uncached compinit
  # plus promptinit to /etc/zshrc, costing ~1s on every interactive shell.
  programs.zsh = {
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };
}
