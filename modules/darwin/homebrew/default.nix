# Homebrew behavior: how brew is managed, upgraded, and cleaned on every switch.
# Package lists live in the sibling bundle files (common.nix, work.nix, ...),
# imported per-host from hosts/*.nix.
{ user, ... }:

{
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true; # take ownership of existing /opt/homebrew without reinstalling
    mutableTaps = true; # taps are declared in the bundles; mutable so the brew CLI still works between rebuilds
  };

  # Covers interactive `brew` only: this lands in /etc/zshenv, which the switch never
  # reads. Activation runs under `env -i` and then `sudo --preserve-env=PATH`, so
  # onActivation.extraEnv below is the only way these reach the `brew bundle` run.
  environment.variables = {
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_ENV_HINTS = "1";
  };

  homebrew = {
    enable = true;
    onActivation = {
      extraEnv = {
        HOMEBREW_NO_ANALYTICS = "1"; # analytics + donation blurb
        # `brew update`'s "analytics moved to InfluxDB" notice. It prints when analytics
        # are off and brew has not recorded showing it. An internal knob (the installer
        # sets it; not in `man brew`) - if a brew upgrade drops it, the rebuild-format
        # rules still collapse the notice.
        HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT = "1";
        HOMEBREW_NO_ENV_HINTS = "1"; # auto-update / `man brew` hint block
        HOMEBREW_NO_UPDATE_REPORT_NEW = "1"; # "==> New Casks" listing
      };
      # "zap" removes every brew/cask not declared in the bundles on each rebuild,
      # so the declared lists are the single source of truth for Homebrew state.
      # Every profile has been audited against its machine before this was enabled.
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
      # --force lets cask upgrades overwrite stale Caskroom artifacts left behind by
      # self-updating apps (otherwise "already an App at..."), and makes zap actually
      # remove strays instead of skipping them when brew is unsure about overwriting.
      extraFlags = [ "--force" ];
    };
    greedyCasks = true; # upgrade self-updating casks too
    # Homebrew 6 removed --no-quarantine with no replacement; the caskDequarantine
    # activation below strips the xattr post-install instead.
  };

  home-manager.sharedModules = [
    (
      { pkgs, lib, ... }:
      let
        mkReconcile = import ../../home/lib/reconcile.nix { inherit pkgs lib; };
      in
      {
        # Prune brew caches and orphaned deps after every bundle run. Runs as the
        # user (brew refuses root), hence a home-manager activation.
        home.activation.brewMaintenance = mkReconcile {
          name = "brew-maintenance";
          text = ''
            _brew=/opt/homebrew/bin/brew
            if [ -x "$_brew" ]; then
              "$_brew" cleanup --prune=all >/dev/null 2>&1 || true
              "$_brew" autoremove >/dev/null 2>&1 || true
            fi
          '';
        };

        # Strip the quarantine xattr from brew-managed cask artifacts so unsigned
        # casks open without a Gatekeeper prompt. Scoped to the Caskroom only;
        # QuickLook plugins strip their own in ../quicklook.nix.
        home.activation.caskDequarantine = mkReconcile {
          name = "cask-dequarantine";
          text = ''
            _caskroom=/opt/homebrew/Caskroom
            if [ -d "$_caskroom" ]; then
              /usr/bin/xattr -d -r com.apple.quarantine "$_caskroom" 2>/dev/null || true
            fi
          '';
        };
      }
    )
  ];
}
