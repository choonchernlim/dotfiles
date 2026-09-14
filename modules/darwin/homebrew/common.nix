# Homebrew packages shared by all profiles: the audited 3-way intersection of
# work/personal/work-atdj. Anything not declared by every host lives in that
# host's own bundle, even if two bundles end up listing the same entry.
#
# cleanup = "zap" (./default.nix) enforces these lists: removing a package here
# uninstalls it on the next rebuild - no manual `brew uninstall`.
{
  homebrew = {
    brews = [
      "bash"
      "coreutils"
      "curl"
      "gh"
      "git-lfs"
      "rsync"
      "shellcheck"
      "tree"
      "uv"
      "wget"
      "yamllint"
      "yarn"

      # Container runtime: colima runs a headless Linux VM, autostarted at login
      # by modules/home/colima.nix. Buildx and Compose install as Docker CLI
      # plugins; modules/home/docker.nix exposes Homebrew's plugin directory.
      "colima"
      "docker"
      "docker-buildx"
      "docker-compose"
      # Provides docker-credential-osxkeychain, which modules/home/docker.nix sets
      # as credsStore so registry logins land in the Keychain, not plaintext.
      "docker-credential-helper"
    ];
    casks = [
      "1password"
      "alfred"
      # greedy = false: these apps update themselves and brew cannot cleanly replace
      # them (agy self-update overwrites brew's binary; Chrome.app is root-owned).
      # brew only guarantees they are installed. agy is kept current by the
      # agyUpdate activation in modules/home/ai/antigravity.nix.
      {
        name = "antigravity-cli";
        greedy = false;
      }
      "brave-browser"
      "firefox"
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "gcloud-cli"
      {
        name = "google-chrome";
        greedy = false;
      }
      "grandperspective"
      "logi-options+"
      "obsidian"
      "rectangle"
      "sublime-text"
      "visual-studio-code"
      "wezterm"
    ];
  };
}
