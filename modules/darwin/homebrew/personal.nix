# Homebrew packages for the personal profile, beyond common.nix.
# cleanup = "zap" (./default.nix): removing an entry uninstalls it on the next rebuild.
{
  homebrew = {
    # Homebrew 6 Tap-Trust: third-party taps must be trusted or `brew bundle`
    # aborts on a fresh bootstrap. redis-stack is personal-only by choice.
    taps = [
      {
        name = "oven-sh/bun";
        trusted = true;
      }
      {
        name = "redis-stack/redis-stack";
        trusted = true;
      }
      {
        name = "terraform-linters/tap";
        trusted = true;
      }
    ];
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
      "minikube"
      "ollama"
      "pipx"
      "yt-dlp"
    ];
    casks = [
      "adobe-creative-cloud"
      "bruno"
      "calibrite-profiler"
      "chatgpt"
      "claude"
      "claude-code@latest"
      "copilot-cli"
      "cyberduck"
      "garmin-basecamp"
      "garmin-express"
      "google-drive"
      "google-gemini"
      "grammarly-desktop"
      "intellij-idea"
      "nordvpn"
      "postman"
      "redis-stack"
      "redis-stack-redisinsight"
      "redis-stack-server"
      "signal"
      "spotify"
      "tflint"
      "trezor-suite"
      "whatsapp"
      "zed"
    ];
  };
}
