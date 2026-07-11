{ user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  # nixpkgs.hostPlatform is set per-host in hosts/*.nix, not here.

  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    primaryUser = user;
    stateVersion = 6;

    # Ports the Ansible mac role: Rosetta 2 so Apple Silicon runs Intel apps.
    # Guarded by a functional test (arch -x86_64) - no-op once installed.
    activationScripts.extraActivation.text = ''
      if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license || true
      fi
    '';

    # system.defaults was originally commented out for Ansible coexistence, but
    # the inventory showed Ansible never managed macOS UI defaults - it is now
    # simply a deliberate-setup task deferred to its own session.
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
  users.users.${user} = {
    home = "/Users/${user}";
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true; # take ownership of existing /opt/homebrew without reinstalling
    mutableTaps = true; # taps (oven-sh/bun, redis-stack, terraform-linters) not yet declared - part of the pending zap-flip audit task
  };
  # Ports Ansible's `brew analytics off` declaratively for fresh machines.
  environment.variables.HOMEBREW_NO_ANALYTICS = "1";

  # home-manager owns zsh completion init (cached compinit) and starship owns
  # the prompt. The nix-darwin defaults would add a second, uncached compinit
  # plus promptinit to /etc/zshrc costing ~1s on every interactive shell.
  programs.zsh = {
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };

  # Package lists live in ./homebrew/{common,personal,work}.nix, imported per-host
  # via hosts/*.nix. Only homebrew *behavior* settings belong here.
  homebrew = {
    enable = true;
    onActivation = {
      # Ansible is retired; "none" remains only until the zap-flip audit task
      # (diff `brew list` vs declared lists, declare or drop each stray, then
      # flip to "zap" for full reproducibility).
      cleanup = "none";
      autoUpdate = true; # Ansible also runs brew update; double-update is fine
      upgrade = true; # upgrade all installed brews on every rebuild
      # --force makes cask upgrades overwrite stale Caskroom artifacts left behind by
      # self-updating apps (e.g. Chrome), which otherwise fail with "already an App at...".
      # Safe with cleanup=none: --force only triggers uninstalls alongside --cleanup/--zap.
      extraFlags = [ "--force" ];
    };
    greedyCasks = true; # ports Ansible's `greedy: true` - upgrade self-updating casks too
    caskArgs.no_quarantine = true; # ports Ansible's post-install quarantine stripping
  };

  # Ports the Ansible cleanup role: prune brew caches and orphaned deps after
  # every bundle run. Runs as the user - brew refuses root. (brew doctor was
  # dropped: informational noise, never actionable in practice.)
  home-manager.sharedModules = [
    (
      { lib, ... }:
      {
        home.activation.brewMaintenance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          _brew=/opt/homebrew/bin/brew
          if [ -x "$_brew" ]; then
            "$_brew" cleanup --prune=all >/dev/null 2>&1 || true
            "$_brew" autoremove >/dev/null 2>&1 || true
          fi
        '';
      }
    )
  ];
}
