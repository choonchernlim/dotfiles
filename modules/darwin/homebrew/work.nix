# Homebrew packages for the work profile, beyond common.nix.
# cleanup = "zap" (./default.nix): removing an entry uninstalls it on the next rebuild.
{
  homebrew = {
    # Homebrew 6 Tap-Trust: third-party taps must be trusted or `brew bundle`
    # aborts on a fresh bootstrap.
    taps = [
      {
        name = "oven-sh/bun";
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
    ];
    # copilot-cli, tflint, zed are cask-only in Homebrew 6.
    casks = [
      "bruno"
      "calibrite-profiler"
      "chatgpt"
      "claude"
      "claude-code@latest"
      "codex"
      "copilot-cli"
      "cyberduck"
      "google-drive"
      "google-gemini"
      "intellij-idea"
      "postman"
      "spotify"
      "tflint"
      "zed"
    ];
  };
}
