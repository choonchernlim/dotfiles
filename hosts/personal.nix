{
  system = "aarch64-darwin"; # use x86_64-darwin for Intel CPU
  # Personal-only system config. Empty for now (Ansible still owns personal packages).
  darwin = { ... }: {
    # Future per-profile personal additions go here. Examples:
    # homebrew.casks = [ "garmin-basecamp" "garmin-express" "grammarly-desktop" "nordvpn" ];
    # homebrew.brews = [ "yt-dlp" ];
  };
}
