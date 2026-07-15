{
  system = "aarch64-darwin"; # use x86_64-darwin for Intel CPU
  # work-atdj profile: standalone homebrew bundle (see homebrew/work-atdj.nix) + quicklook.
  darwin = {
    imports = [
      ../modules/darwin/homebrew/work-atdj.nix
      ../modules/darwin/quicklook.nix
    ];
  };
  # Home feature modules this host gets (core config is always included).
  home = {
    imports = [
      ../modules/home/zsh.nix
      ../modules/home/gcloud.nix
      ../modules/home/ai.nix
      ../modules/home/colima.nix
      ../modules/home/gitea.nix
    ];
  };
}
