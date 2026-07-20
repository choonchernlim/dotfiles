{
  system = "aarch64-darwin"; # use x86_64-darwin for Intel CPU
  # Work profile: pick the homebrew bundles this host gets.
  darwin = {
    imports = [
      ../modules/darwin/homebrew/common.nix
      ../modules/darwin/homebrew/work.nix
      ../modules/darwin/quicklook.nix
    ];
  };
  # Home feature modules this host gets (core config is always included).
  home = {
    imports = [
      ../modules/home/zsh.nix
      ../modules/home/mise.nix
      ../modules/home/gcloud.nix
      ../modules/home/ghostty.nix
      ../modules/home/ai.nix
      ../modules/home/colima.nix
      ../modules/home/docker.nix
      ../modules/home/gitea.nix
      ../modules/home/zscaler.nix
    ];
  };
}
