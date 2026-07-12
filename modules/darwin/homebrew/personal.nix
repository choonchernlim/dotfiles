# Homebrew packages for the personal profile (ported from Ansible role homebrew_personal).
#
# homebrew.onActivation.cleanup = "zap" (set in modules/darwin/default.nix) means
# removing a package from these lists uninstalls it on the next rebuild.
{
  homebrew = {
    # Kept on personal only - the work-profile zap audit dropped this tap and
    # its casks; the personal audit (2026-07-12) chose to keep Redis Stack.
    taps = [
      "redis-stack/redis-stack"
    ];
    brews = [
      "yt-dlp"
    ];
    casks = [
      "adobe-creative-cloud"
      "garmin-basecamp"
      "garmin-express"
      "grammarly-desktop"
      "nordvpn"
      "redis-stack"
      "redis-stack-redisinsight"
      "redis-stack-server"
      "trezor-suite"
      "whatsapp"
    ];
  };
}
