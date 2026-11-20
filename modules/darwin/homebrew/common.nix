# Homebrew packages shared by all profiles: the audited 3-way intersection of
# work/personal/work-atdj. Anything not declared by every host lives in that
# host's own bundle, even if two bundles end up listing the same entry.
#
# cleanup = "zap" (./default.nix) enforces these lists: removing a package here
# uninstalls it on the next rebuild - no manual `brew uninstall`.
{
  # A self-updated agy (`agy update`) replaces brew's command wrapper with a
  # real binary, and brew then refuses to install the antigravity-cli cask over
  # it. Clear that stray binary (not a `#!` script, not a symlink) before the
  # homebrew step so the wrapper can install. Brew owns agy; see docs/gotchas.md.
  system.activationScripts.extraActivation.text = ''
    _agy=/opt/homebrew/bin/agy
    if [ -f "$_agy" ] && [ ! -L "$_agy" ] && [ "$(/usr/bin/head -c 2 "$_agy")" != "#!" ]; then
      /bin/rm -f "$_agy"
    fi
  '';

  homebrew = {
    brews = [
      "bash"
      "coreutils"
      "curl"
      "exiftool"
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
      # brew owns agy updates: the cask disables agy's self-update, so never run
      # `agy update` (it overwrites brew's command wrapper; see docs/gotchas.md).
      "antigravity-cli"
      "brave-browser"
      "chatgpt"
      "firefox"
      "font-hack-nerd-font"
      "font-meslo-lg-nerd-font"
      "gcloud-cli"
      # greedy = false: Chrome updates itself and brew cannot cleanly replace it
      # (Chrome.app is root-owned); brew only guarantees it is installed.
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
