# Homebrew packages for the work-atdj profile - standalone starting copy of common.nix's full
# taps/brews/casks plus work.nix's colima/docker/docker-compose (general-purpose container
# runtime, autostarted at login by modules/home/colima.nix; also used for the gitea runtime).
# Deliberately NOT `imports = [ common.nix work.nix ]` - a standalone copy means the user
# pruning this list down later never affects work/personal, and vice versa.
{
  homebrew = {
    taps = [
    ];
    brews = [
      "bash"
      "coreutils"
      "curl"
      "gh"
      "git-lfs"
      "jq"
      "rsync"
      "rtk"
      "shellcheck"
      "tree"
      "uv"
      "wget"
      "yamllint"
      "yarn"
      "colima"
      "docker"
      "docker-compose"
    ];
    casks = [
      "1password"
      "alfred"
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
      "rectangle"
      "sublime-text"
      "visual-studio-code"
      "wezterm"
    ];
  };
}
