{
  system = "aarch64-darwin"; # use x86_64-darwin for Intel CPU
  # Work profile: pick the homebrew bundles this host gets.
  darwin = {
    imports = [
      ../modules/darwin/homebrew/common.nix
      ../modules/darwin/homebrew/work.nix
    ];
  };
}
