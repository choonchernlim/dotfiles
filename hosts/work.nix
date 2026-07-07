{
  system = "aarch64-darwin"; # use x86_64-darwin for Intel CPU
  # Work-only system config. Empty for now (Ansible still owns work packages).
  darwin = { ... }: {
    # Future per-profile work additions go here. Examples:
    # homebrew.casks = [ "android-studio" ];
    # homebrew.brews = [ "node" "watchman" ];
  };
}
