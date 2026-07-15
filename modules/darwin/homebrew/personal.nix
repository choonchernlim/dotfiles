# Homebrew packages for the personal profile (ported from Ansible role homebrew_personal).
#
# homebrew.onActivation.cleanup = "zap" (set in modules/darwin/default.nix) means
# removing a package from these lists uninstalls it on the next rebuild.
{
  homebrew = {
    # redis-stack/redis-stack: kept on personal only - the work-profile zap audit
    # dropped this tap and its casks; the personal audit (2026-07-12) chose to keep
    # Redis Stack. oven-sh/bun and terraform-linters/tap were moved down from
    # common.nix in the 2026-07-15 all-hosts audit (not declared on work-atdj, so not
    # part of the 3-way intersection).
    taps = [
      "oven-sh/bun"
      "redis-stack/redis-stack"
      "terraform-linters/tap"
    ];
    # azure-cli..pipx moved down from common.nix in the 2026-07-15 all-hosts audit (not
    # declared on work-atdj, so not part of the 3-way intersection).
    brews = [
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
      "yt-dlp"
    ];
    # bruno..zed moved down from common.nix in the 2026-07-15 all-hosts audit (not
    # declared on work-atdj, so not part of the 3-way intersection).
    casks = [
      "adobe-creative-cloud"
      "bruno"
      "calibrite-profiler"
      "chatgpt-classic"
      "claude"
      "claude-code"
      "copilot-cli"
      "cyberduck"
      "garmin-basecamp"
      "garmin-express"
      "ghostty"
      "google-drive"
      "google-gemini"
      "grammarly-desktop"
      "intellij-idea"
      "nordvpn"
      "postman"
      "readdle-spark"
      "redis-stack"
      "redis-stack-redisinsight"
      "redis-stack-server"
      "spotify"
      "tflint"
      "trezor-suite"
      "whatsapp"
      "zed"
    ];
  };
}
