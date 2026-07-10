# Homebrew packages for the work profile (ported from Ansible role homebrew_work).
#
# Removing a package from these lists does NOT uninstall it while
# homebrew.onActivation.cleanup = "none" - run `brew uninstall <pkg>` manually.
{
  homebrew = {
    brews = [
      "node"
      "watchman"
    ];
    casks = [
      "android-studio"
    ];
    # Ansible's work "absent" list - homebrew_work actively uninstalled the personal
    # casks on the work profile. Not expressible while cleanup = "none"; revisit when
    # cleanup flips to "zap" (undeclared casks are then removed automatically).
    # casks absent:
    #   garmin-basecamp, garmin-express, grammarly-desktop, nordvpn
  };
}
