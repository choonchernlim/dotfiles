# v002 Fix agy cask conflict

## Shared understanding
`rebuild work` fails in the homebrew step: `already a Command Wrapper at '/opt/homebrew/bin/agy'`. The `agyUpdate` activation runs `agy update`, which replaced brew's symlink with a real binary and left the Caskroom empty. The new antigravity-cli cask installs a command wrapper (self-update disabled) at that path. Decision: brew owns agy updates; remove the self-update path and clean the stray binary in nix.

## Assumptions
- Confirmed: brew owns updates.
- Unconfirmed: the cask no longer needs `greedy = false` (it is not `auto_updates`).

## Definition of done
- Static checks pass (flake check, statix, deadnix, activation shellcheck, rebuild-format, check-warnings).
- After the user runs `rebuild work`: antigravity-cli installs, `/opt/homebrew/bin/agy` is a `#!` wrapper, `agy --version` is 1.5.9, and a second rebuild is clean.
