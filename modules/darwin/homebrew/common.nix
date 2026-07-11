# Homebrew packages shared by all profiles (ported from Ansible role homebrew_common).
#
# homebrew.onActivation.cleanup = "zap" enforces this list automatically on every
# rebuild - removing a package here uninstalls it (and prunes now-orphaned deps) on
# the next `rebuild`. No manual `brew uninstall` needed.
{
  homebrew = {
    # Already tapped + trusted on this machine. On a fresh machine, if `brew bundle`
    # blocks on an untrusted tap, run `brew trust --tap <tap>` once.
    taps = [
      "oven-sh/bun"
      "terraform-linters/tap"
    ];
    brews = [
      "azure-cli"
      "bash"
      "black"
      "bun"
      "cloud-sql-proxy"
      "coreutils"
      "curl"
      "exiftool"
      "ffmpeg"
      "firefoxpwa"
      "gh"
      "git-lfs"
      "go"
      "gpsbabel"
      "graphviz"
      "herdr"
      "hf"
      "htop"
      "imagemagick"
      "jq"
      "k6"
      "kubectl"
      "lazygit"
      "minikube"
      "ollama"
      "pipx"
      "rsync"
      "rtk"
      "shellcheck"
      "tree"
      "uv"
      "wget"
      "yamllint"
      "yarn"
      # Moved to nixpkgs via home-manager (programs.starship, programs.direnv,
      # programs.zsh.*) when the Ansible ohmyzsh role was ported; zshReconcile
      # uninstalls the brew copies.
      # "direnv"
      # "starship"
      # "zsh-autosuggestions"
      # "zsh-syntax-highlighting"
      # Retired in the dev-toolchain rewrite: nvm/tfenv replaced by mise
      # (programs.mise + home/.config/mise/config.toml), maven dropped with
      # java/sdkman. zshReconcile uninstalls the brew copies.
      # "maven"
      # "nvm"
      # "tfenv"
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
      "bruno"
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
      # iterm2 dropped when Ansible retired - WezTerm + ghostty are the
      # terminals; ghosttyReconcile uninstalls the cask and removes its config.
      # "iterm2"
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
    # Already removed from this machine by Ansible; kept here as historical record.
    # Now that cleanup = "zap", any of these would also be removed automatically if
    # ever reinstalled outside this list.
    # brews absent:
    #   allure, ansible-lint (remove first before removing ansible), ansible, checkov,
    #   composer, dialog, gemini-cli, gobject-introspection, nghttp2, tldr
    # casks absent:
    #   anaconda, chronosync, cleanmymac, docker, google-backup-and-sync, i1profiler,
    #   mamp, nomachine, raindropio, scroll-reverser, skitch, textmate
  };
}
