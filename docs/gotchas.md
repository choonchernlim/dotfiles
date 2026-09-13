# Gotchas

Known quirks and non-obvious behavior in this repo.

**Homebrew cleanup is `"zap"` on every profile.**
`modules/darwin/homebrew/default.nix` sets `homebrew.onActivation.cleanup = "zap"` - packages not declared in `modules/darwin/homebrew/{common,work,personal,work-atdj}.nix` are removed automatically on each switch. Declared lists are the single source of truth; there is no manual `brew uninstall` step.

**`rebuild` refuses a profile that doesn't match this machine.**
Every switch writes the applied profile to `/etc/dotfiles-profile` (`modules/darwin/system.nix`). `rebuild` with no argument reuses it; `rebuild <other>` aborts unless you pass `--force`, because zap would uninstall this machine's packages. The marker does not exist until the first bootstrap, so `bootstrap.sh` always needs the profile argument.

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `codex plugin add`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild`. To keep a plugin, declare it in nix - for Claude that means `enabledPlugins`/`extraKnownMarketplaces` in `home/ai/settings/claude.json`, which the reconcile reads as its keep-set. See AGENTS.md "AI Agent Plugin Reconcile" for details.

**Skills live in one hub: `~/.agents/skills`.**
`modules/home/ai/default.nix` links `~/.agents/skills` at `home/ai/skills/`. Codex, Copilot and OpenCode discover that path natively and get no skills link of their own - adding one back would list every skill twice. Claude Code and Antigravity do not read `~/.agents`, so `~/.claude/skills` and `~/.gemini/antigravity-cli/skills` are directory links at the hub. New skill directories are live for every agent, no rebuild. Codex still writes its bundled system skills into `~/.codex/skills/.system/`; nix never touches that directory (`home/ai/skills/.system/` stays gitignored as a backstop). Copilot does not document symlink following - if its skills ever go missing, the documented fallback is a `~/.copilot/skills` link at the hub in `modules/home/ai/copilot.nix`.

**home-manager never removes a managed symlink whose path becomes a directory.**
Its link cleanup skips any old-generation link whose relative path still *exists* in the new generation - and a directory counts. Switching `~/.codex/skills` from one directory link to per-skill links inside a real directory therefore left the old link in place; the new per-file links were then created *through* it, i.e. inside the git checkout, moving the real skill dirs aside as `<name>.hm-bak` and leaving self-referencing symlinks that got committed. Never convert a linked directory into per-file links without first removing the old link in an activation ordered before `linkGeneration`; with the hub layout no such transition remains. `modules/home/legacy.nix` sweeps the one stale `~/.codex/skills` link this left behind.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, OpenCode, and Antigravity. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**The Claude model is set only in `home/ai/settings/claude.json`.**
`ANTHROPIC_MODEL` is deliberately not exported by nix: the env var overrides the settings `model` key and used to make that key dead. If `/model` reports an env override, something outside this repo is setting it.

**The shell setup is deliberately minimal.**
oh-my-zsh, p10k, and the old alias pack were dropped - autosuggestions/highlighting come from nixpkgs, the prompt is starship (`home/.config/starship.toml`, live-editable), and the only aliases are `rebuild`, `personal_claude`, and the Langfuse-tagging wrappers for `claude`/`codex`. nvm and sdkman were dropped for mise (`home/.config/mise/config.toml`).

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**`rebuild` auto-syncs the repo before applying.** `rebuild.sh` runs `git pull --rebase --autostash` when on `main` (skipped with a notice on any other branch) so a machine always applies the latest committed config. Autostash means uncommitted edits survive the pull. If the pull fails (offline, conflict), the rebuild aborts rather than applying on top of unresolved state.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.

**An agent replacing its nix-symlinked config file can hard-abort `rebuild`.** home-manager
claims a config path with an out-of-store symlink; if the agent CLI then writes its own
runtime state into that path (atomic tmp+rename), the symlink is replaced by a real file.
On the next rebuild, home-manager's `checkLinkTargets` tries to move that file aside to
`<path>.hm-bak` before relinking - and if a `.hm-bak` from a previous occurrence is still
sitting there, it refuses rather than overwrite it, aborting activation with "would be
clobbered by backing up". This happened to `~/.gemini/antigravity-cli/settings.json`. Two-part
fix: (1) that file is merge-reconciled by `antigravitySettings` (`modules/home/ai/antigravity.nix`)
instead of symlinked - it owns only the nix-declared keys and passes through everything the
agent wrote, same pattern as `modules/home/docker.nix`; (2) generally, `rebuild.sh` sweeps stale
`*.hm-bak` files under all agent config dirs *before* invoking `darwin-rebuild`, since the
per-agent sweeps run as activation scripts - too late, after `checkLinkTargets` already aborted.
If another agent starts fighting nix for one of its own settings files, apply the same
merge-reconcile pattern rather than `force = true` on the symlink - `force = true` wins but
silently discards whatever the agent had written.
