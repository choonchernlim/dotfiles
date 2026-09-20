# Homebrew packages unique to the work-atdj profile, beyond common.nix.
# Extend by hand; deliberately not built from work.nix/personal.nix so pruning
# either of those never affects this machine.
# cleanup = "zap" (./default.nix): removing an entry uninstalls it on the next rebuild.
{
  homebrew = {
    taps = [ ];
    brews = [ ];
    # claude is the desktop app; claude-code@latest is the CLI that
    # modules/home/ai/claude configures (it no-ops while the binary is absent).
    casks = [
      "claude"
      "claude-code@latest"
    ];
  };
}
