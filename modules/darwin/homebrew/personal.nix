# Homebrew packages for the personal profile (ported from Ansible role homebrew_personal).
#
# homebrew.onActivation.cleanup = "zap" (set in modules/darwin/default.nix) means
# removing a package from these lists uninstalls it on the next rebuild.
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
