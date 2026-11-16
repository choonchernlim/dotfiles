# v003 Single sudo prompt

## Shared understanding
`rebuild` asks for a password or Touch ID several times, mostly during cask upgrades. `rebuild.sh` already warms the sudo cache once and keeps it alive, but sudo 1.9.17 caches credentials per terminal (`timestamp_type=tty`) and runs each command in a new pty (`use_pty`). `sudo darwin-rebuild` and then nix-darwin's `sudo --user=<you> brew bundle` each open a new pty, so brew's own sudo calls never see the warm cache. Decision: `Defaults:<user> timestamp_type=global`, so one prompt covers the whole rebuild. Accepted tradeoff: whenever the cache is warm (5 min after any sudo), every terminal and process of the user gets sudo without a prompt.

## Assumptions
- Confirmed: Touch ID PAM stays as is; `security.sudo.extraConfig` is `nullOr lines` and merges with nix-darwin's terminfo lines.
- Confirmed: applies to every profile (`modules/darwin/system.nix` is shared).
- Unconfirmed: every repeated prompt is sudo; a cask installer's own macOS authorization dialog would still prompt.

## Definition of done
- Static checks pass: `nix flake check --impure --no-build`, `scripts/check-warnings.sh`, `nix fmt`, `visudo -c` on the generated drop-in.
- After the user's rebuild, `sudo sudo -u "$USER" sudo -n true` succeeds while the cache is warm.
- A rebuild that upgrades casks prompts exactly once.
