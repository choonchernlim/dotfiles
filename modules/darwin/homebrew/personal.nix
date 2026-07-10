# Homebrew packages for the personal profile (ported from Ansible role homebrew_personal).
#
# Removing a package from these lists does NOT uninstall it while
# homebrew.onActivation.cleanup = "none" - run `brew uninstall <pkg>` manually.
{
  homebrew = {
    brews = [
      "yt-dlp"
    ];
    casks = [
      "garmin-basecamp"
      "garmin-express"
      "grammarly-desktop"
      "nordvpn"
    ];
  };
}
