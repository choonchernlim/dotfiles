# Gotchas

Known quirks and non-obvious behavior in this repo.

**Homebrew cleanup is `"zap"` on both profiles.**
`modules/darwin/default.nix` sets `homebrew.onActivation.cleanup = "zap"` - packages not declared in `modules/darwin/homebrew/{common,work,personal}.nix` are removed automatically on each switch. Declared lists are the single source of truth; there is no manual `brew uninstall` step. Both profiles have had their zap-flip audit (work first, personal on 2026-07-12 before its first bootstrap).

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild work`. To keep a plugin, declare it in nix. See AGENTS.md "AI Agent Plugin Reconcile" for details.

**rtk (Rust Token Killer) hooks are nix-managed - do not run `rtk init`.**
`rtk` rewrites Bash tool calls to use token-optimized proxies (e.g. `git status` -> `rtk git status`). The binary comes from Homebrew; hooks for Claude, Copilot, and opencode are declared in `home/ai/` as nix-owned symlinks. Running `rtk init` would overwrite those symlinks with real files that get reverted on the next `rebuild work`.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, and OpenCode. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**The shell setup is deliberately minimal.**
oh-my-zsh, p10k, and the old alias pack were dropped (not ported) when the Ansible `ohmyzsh` role migrated here - autosuggestions/highlighting come from nixpkgs, the prompt is starship (`home/.config/starship.toml`, live-editable), and the only aliases are `rebuild` and `personal_claude`. Likewise nvm and sdkman were dropped for mise (`home/.config/mise/config.toml`), taking shell startup from ~4s to well under 1s. The `zshReconcile` activation script sweeps all the stale artifacts on every rebuild.

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**`rebuild` auto-syncs the repo before applying.** `rebuild.sh` runs `git pull --rebase --autostash` when on `main` (skipped with a notice on any other branch) so a machine always applies the latest committed config, not stale local state - useful when working across multiple machines. Autostash means uncommitted edits survive the pull. If the pull fails (offline, conflict), the rebuild aborts rather than applying on top of unresolved state - resolve the conflict/network issue and re-run.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.
