# Homebrew packages shared by all profiles (ported from Ansible role homebrew_common).
# Audited 2026-07-15 against all 3 host bundles (work/personal/work-atdj) - this is the
# true 3-way intersection: only packages every host actually declares live here. Anything
# not declared by all 3 lives in that host's own bundle file instead (work.nix /
# personal.nix / work-atdj.nix), even if that means duplicating the same entry across two
# of them.
#
# homebrew.onActivation.cleanup = "zap" enforces this list automatically on every
# rebuild - removing a package here uninstalls it (and prunes now-orphaned deps) on
# the next `rebuild`. No manual `brew uninstall` needed.
{
  homebrew = {
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

      # General-purpose container runtime - colima runs a headless Linux VM,
      # autostarted at login by modules/home/colima.nix. Currently used for the
      # local Gitea git server (modules/home/gitea.nix, work/work-atdj only);
      # not gitea-specific. docker-compose is the standalone (hyphenated)
      # formula - see gitea.nix for why that form is used.
      "colima"
      "docker"
      "docker-compose"

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
    # antigravity-cli is a formula in the Ansible list but cask-only in Homebrew 6,
    # so it lives here.
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
    # Ansible's "absent" lists - packages actively uninstalled by homebrew_common.
    # Already removed from this machine; kept here as historical record.
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
