# System-level config every host gets. Package bundles and darwin feature
# modules (quicklook) are picked per-host in hosts/*.nix.
{
  imports = [
    ./system.nix # nix daemon handoff, sudo Touch ID, Rosetta, profile marker, zsh
    ./homebrew # homebrew behavior (zap cleanup, upgrades, maintenance activations)
  ];
}
