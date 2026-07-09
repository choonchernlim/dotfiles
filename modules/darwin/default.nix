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
    # system.defaults commented out to preserve existing macOS UI settings during
    # Ansible coexistence. Uncomment and customise once fully migrated to Nix.
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
    mutableTaps = true; # preserve Ansible-managed taps (oven-sh/bun, redis-stack, terraform-linters)
  };
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "none"; # was "zap" - keep Ansible-installed brews/casks intact
      autoUpdate = true; # Ansible also runs brew update; double-update is fine
      upgrade = true; # upgrade all installed brews on every rebuild
      # extraFlags = [ "--force" ];  # disabled: not needed with cleanup=none
    };
    brews = [
      "herdr"
      "rtk"
    ];
    casks = [
      "wezterm"
      "claude-code"
    ];
  };
}
