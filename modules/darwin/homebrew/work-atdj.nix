# Homebrew packages unique to the work-atdj profile - now imports common.nix
# (hosts/work-atdj.nix) for the shared baseline, so this file only needs whatever is
# specific to this machine and not needed by work/personal too.
#
# Empty for now: the 2026-07-15 all-hosts audit found every package this profile had
# declared was already covered by common.nix, so there was nothing left to keep here.
# The user extends this file by hand as machine-specific needs come up - it is
# deliberately not built from importing work.nix/personal.nix, so pruning either of
# those never affects this file, and vice versa.
{
  homebrew = {
    taps = [ ];
    brews = [ ];
    casks = [ ];
  };
}
