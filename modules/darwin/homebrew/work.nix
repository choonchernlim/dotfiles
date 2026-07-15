# Homebrew packages for the work profile (ported from Ansible role homebrew_work).
#
# homebrew.onActivation.cleanup = "zap" enforces this list automatically on every
# rebuild - removing a package here uninstalls it on the next `rebuild`.
{
  homebrew = {
    taps = [
      "oven-sh/bun"
      "terraform-linters/tap"
    ];
    brews = [
      # node moved to mise (was shadowed by nvm's node on PATH anyway);
      # zshReconcile uninstalls the brew copy.
      # "node"
      # watchman was for the mobile/React Native toolchain; dropped along with
      # android-studio, cocoapods, fastlane when mobile dev was retired.
      # "watchman"

      # Moved down from common.nix in the 2026-07-15 all-hosts audit - not
      # declared on work-atdj, so not part of the 3-way intersection.
      "azure-cli"
      "black"
      "bun"
      "cloud-sql-proxy"
      "exiftool"
      "ffmpeg"
      "firefoxpwa"
      "go"
      "gpsbabel"
      "graphviz"
      "herdr"
      "hf"
      "htop"
      "imagemagick"
      "k6"
      "kubectl"
      "lazygit"
      "minikube"
      "ollama"
      "pipx"
    ];
    # copilot-cli, tflint, zed were formulae in the Ansible list but are cask-only in
    # Homebrew 6, so they live here (antigravity-cli is the same case but stayed in
    # common.nix - see there). Moved down from common.nix in the 2026-07-15 audit - not
    # declared on work-atdj, so not part of the 3-way intersection.
    casks = [
      # android-studio: mobile dev retired, no longer needed.
      # "android-studio"
      "bruno"
      "calibrite-profiler"
      "chatgpt-classic"
      "claude"
      "claude-code"
      "codex"
      "copilot-cli"
      "cyberduck"
      "ghostty"
      "google-drive"
      "google-gemini"
      "intellij-idea"
      "postman"
      "readdle-spark"
      "spotify"
      "tflint"
      "zed"
    ];
    # Ansible's work "absent" list - homebrew_work actively uninstalled the personal
    # casks on the work profile. Already removed from this machine; kept as
    # historical record. cleanup = "zap" now enforces absence automatically.
    # casks absent:
    #   garmin-basecamp, garmin-express, grammarly-desktop, nordvpn
  };
}
