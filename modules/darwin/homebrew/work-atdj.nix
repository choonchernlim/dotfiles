# Homebrew packages unique to the work-atdj profile, beyond common.nix.
# Empty so far: the last audit found everything this machine needs already in
# common.nix. Extend by hand; deliberately not built from work.nix/personal.nix
# so pruning either of those never affects this machine.
{
  homebrew = {
    taps = [ ];
    brews = [ ];
    casks = [ ];
  };
}
