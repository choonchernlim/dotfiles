# Homebrew packages for the work profile (ported from Ansible role homebrew_work).
#
# homebrew.onActivation.cleanup = "zap" enforces this list automatically on every
# rebuild - removing a package here uninstalls it on the next `rebuild`.
{
  homebrew = {
    brews = [
      # node moved to mise (was shadowed by nvm's node on PATH anyway);
      # zshReconcile uninstalls the brew copy.
      # "node"
      # watchman was for the mobile/React Native toolchain; dropped along with
      # android-studio, cocoapods, fastlane when mobile dev was retired.
      # "watchman"
    ];
    casks = [
      # android-studio: mobile dev retired, no longer needed.
      # "android-studio"
    ];
    # Ansible's work "absent" list - homebrew_work actively uninstalled the personal
    # casks on the work profile. Already removed from this machine; kept as
    # historical record. cleanup = "zap" now enforces absence automatically.
    # casks absent:
    #   garmin-basecamp, garmin-express, grammarly-desktop, nordvpn
  };
}
