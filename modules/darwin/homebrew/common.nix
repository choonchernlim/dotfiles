# Homebrew packages shared by all profiles (ported from Ansible role homebrew_common).
#
# Removing a package from these lists does NOT uninstall it while
# homebrew.onActivation.cleanup = "none" - run `brew uninstall <pkg>` manually.
# Once fully migrated off Ansible, cleanup = "zap" will enforce absence automatically.
{
  homebrew = {
    # Already tapped + trusted on this machine. On a fresh machine, if `brew bundle`
    # blocks on an untrusted tap, run `brew trust --tap <tap>` once.
    taps = [
      "oven-sh/bun"
      "redis-stack/redis-stack"
      "terraform-linters/tap"
    ];
    brews = [
      "azure-cli"
      "bash"
      "black"
      "bun"
      "coreutils"
      "curl"
      "direnv"
      "exiftool"
      "ffmpeg"
      "go"
      "gpsbabel"
      "graphviz"
      "herdr"
      "hf"
      "htop"
      "imagemagick"
      "jq"
      "kubectl"
      "lazygit"
      "maven"
      "minikube"
      "nvm"
      "ollama"
      "pipx"
      "rsync"
      "rtk"
      "shellcheck"
      "starship"
      "tfenv"
      "tree"
      "uv"
      "wget"
      "yamllint"
      "yarn"
      "zsh-autosuggestions"
      "zsh-syntax-highlighting"
    ];
    # antigravity-cli, copilot-cli, tflint, zed were formulae in the Ansible list
    # but are cask-only in Homebrew 6, so they live here.
    casks = [
      "1password"
      "alfred"
      # Self-updating apps that brew cannot cleanly upgrade here are pinned greedy=false:
      # - antigravity-cli: agy self-update replaces brew's binary at /opt/homebrew/bin/agy,
      #   so a greedy upgrade always fails with "already a Binary" and rolls back.
      # - google-chrome: /Applications/Google Chrome.app is root-owned (legacy Ansible sudo
      #   install); brew runs unprivileged during activation and cannot replace it.
      # Both apps keep themselves up to date; brew only guarantees they are installed.
      {
        name = "antigravity-cli";
        greedy = false;
      }
      "brave-browser"
      "calibrite-profiler"
      "chatgpt"
      "claude"
      "claude-code"
      "copilot-cli"
      "cyberduck"
      "firefox"
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "gcloud-cli"
      "ghostty"
      {
        name = "google-chrome";
        greedy = false;
      }
      "google-drive"
      "google-gemini"
      "grandperspective"
      "intellij-idea"
      "iterm2"
      "logi-options+" # was logi-options-plus in Ansible; renamed upstream
      "postman"
      "rancher"
      "readdle-spark"
      "rectangle"
      "spotify"
      "sublime-text"
      "tflint"
      "visual-studio-code"
      "wezterm"
      "zed"
    ];
    # Ansible's "absent" lists - packages actively uninstalled by homebrew_common.
    # Not expressible in nix-darwin while cleanup = "none"; already removed from this
    # machine by Ansible. Revisit when cleanup flips to "zap" (absence becomes automatic).
    # brews absent:
    #   allure, ansible-lint (remove first before removing ansible), ansible, checkov,
    #   composer, dialog, gemini-cli, gobject-introspection, nghttp2, tldr
    # casks absent:
    #   anaconda, chronosync, cleanmymac, docker, google-backup-and-sync, i1profiler,
    #   mamp, nomachine, raindropio, scroll-reverser, skitch, textmate
  };
}
