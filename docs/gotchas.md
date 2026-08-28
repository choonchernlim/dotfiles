# Gotchas

Known quirks and non-obvious behavior in this repo.

**Homebrew cleanup is `"zap"` on both profiles.**
`modules/darwin/default.nix` sets `homebrew.onActivation.cleanup = "zap"` - packages not declared in `modules/darwin/homebrew/{common,work,personal}.nix` are removed automatically on each switch. Declared lists are the single source of truth; there is no manual `brew uninstall` step. Both profiles have had their zap-flip audit (work first, personal on 2026-07-12 before its first bootstrap).

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild work`. To keep a plugin, declare it in nix. See AGENTS.md "AI Agent Plugin Reconcile" for details.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, and OpenCode. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**The shell setup is deliberately minimal.**
oh-my-zsh, p10k, and the old alias pack were dropped (not ported) when the Ansible `ohmyzsh` role migrated here - autosuggestions/highlighting come from nixpkgs, the prompt is starship (`home/.config/starship.toml`, live-editable), and the only aliases are `rebuild` and `personal_claude`. Likewise nvm and sdkman were dropped for mise (`home/.config/mise/config.toml`), taking shell startup from ~4s to well under 1s. The one-time `legacy.nix` sweep removes the stale artifacts (retired brews are removed by homebrew `cleanup = "zap"`).

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**`rebuild` auto-syncs the repo before applying.** `rebuild.sh` runs `git pull --rebase --autostash` when on `main` (skipped with a notice on any other branch) so a machine always applies the latest committed config, not stale local state - useful when working across multiple machines. Autostash means uncommitted edits survive the pull. If the pull fails (offline, conflict), the rebuild aborts rather than applying on top of unresolved state - resolve the conflict/network issue and re-run.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.

**An agent replacing its nix-symlinked config file can hard-abort `rebuild`.** home-manager
claims a config path with an out-of-store symlink; if the agent CLI then writes its own
runtime state into that path (atomic tmp+rename), the symlink is replaced by a real file.
On the next rebuild, home-manager's `checkLinkTargets` tries to move that file aside to
`<path>.hm-bak` before relinking - and if a `.hm-bak` from a previous occurrence is still
sitting there, it refuses rather than overwrite it, aborting activation with "would be
clobbered by backing up". This happened to `~/.gemini/antigravity-cli/settings.json` (agy
writes `trustedWorkspaces`/`permissions` into it at runtime). Two-part fix: (1) for that
specific file, `modules/home/ai.nix`'s `antigravitySettings` reconcile replaced the symlink
with a jq merge that owns only the nix-declared keys and passes through everything the
agent wrote (same pattern as `modules/home/docker.nix` for `~/.docker/config.json`, which
`docker login`/`gcloud` also write into); (2) generally, `rebuild.sh` now sweeps stale
`*.hm-bak` files under all agent config dirs *before* invoking `darwin-rebuild`, since
`aiReconcile`'s own `.hm-bak` sweep (`modules/home/ai.nix`) runs as a home-manager
activation script - too late, after `checkLinkTargets` already aborted. If another agent
(claude, copilot) starts fighting nix for one of its own settings files, apply the same
merge-reconcile pattern rather than `force = true` on the symlink - `force = true` wins but
silently discards whatever the agent had written.
