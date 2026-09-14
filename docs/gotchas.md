<!--
Purpose: Records runtime behaviors that can surprise maintainers and their safe response.
Type: reference
-->

# Gotchas

Audience: maintainers diagnosing rebuild, runtime-state, or tool-discovery behavior.

Known quirks and non-obvious behavior in this repo.

**Homebrew cleanup is `"zap"` on every profile.**
`modules/darwin/homebrew/default.nix` sets `homebrew.onActivation.cleanup = "zap"` - packages not declared in `modules/darwin/homebrew/{common,work,personal,work-atdj}.nix` are removed automatically on each switch. Declared lists are the single source of truth; there is no manual `brew uninstall` step.

**Docker CLI plugins come from Homebrew.**

- Ownership: [Docker toolchain](architecture.md#docker-toolchain)
- Reconcile: exposes Homebrew's plugin directory and removes only a broken
  per-user Buildx link
- Verification: `docker buildx version` succeeds after `rebuild`

**`rebuild` refuses a profile that doesn't match this machine.**
Each switch records its profile in `/etc/dotfiles-profile`. A mismatched
explicit profile aborts unless `--force` is present because zap can remove
host-specific packages. The first `bootstrap.sh` call therefore requires a
profile argument.

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `codex plugin add`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild`. To keep a plugin, declare it in nix - for Claude that means `enabledPlugins`/`extraKnownMarketplaces` in `home/ai/settings/claude.json`, which the reconcile reads as its keep-set. See AGENTS.md "AI Agent Plugin Reconcile" for details.

**Skills live in one hub: `~/.agents/skills`.**
The [architecture guide](architecture.md#how-symlinks-work) owns the link
layout. Never add another Codex, Copilot, or OpenCode skills link because it
would list each skill twice.

New skill directories become live without rebuilding. Codex owns
`~/.codex/skills/.system/`; Nix leaves that directory alone. If Copilot stops
following the hub, its fallback belongs in `modules/home/ai/copilot.nix`.

**home-manager never removes a managed symlink whose path becomes a directory.**
Link cleanup skips an old path when that relative path still exists, including
as a directory. A directory-link to per-file-link conversion can therefore
write through the stale link into the repository.

Remove the old link in an activation ordered before `linkGeneration`.
`modules/home/legacy.nix` handles the known stale `~/.codex/skills` link.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, OpenCode, and Antigravity. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**The Claude model is set only in `home/ai/settings/claude.json`.**
`ANTHROPIC_MODEL` is deliberately not exported by nix: the env var overrides the settings `model` key and used to make that key dead. If `/model` reports an env override, something outside this repo is setting it.

**The shell setup is deliberately minimal.**
Nixpkgs supplies autosuggestions and highlighting, while Starship supplies the
prompt. The retained aliases are `rebuild`, `personal_claude`, and the
Langfuse wrappers. Mise replaces nvm and sdkman.

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**`rebuild` auto-syncs the repo before applying.** `rebuild.sh` runs `git pull --rebase --autostash` when on `main` (skipped with a notice on any other branch) so a machine always applies the latest committed config. Autostash means uncommitted edits survive the pull. If the pull fails (offline, conflict), the rebuild aborts rather than applying on top of unresolved state.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.

**An agent replacing its Nix-symlinked config file can abort `rebuild`.**
An atomic runtime write can replace a managed symlink with a regular file.
During the next rebuild, `checkLinkTargets` tries to back it up before
relinking. An existing `.hm-bak` makes that safety check abort.

`antigravitySettings` merge-reconciles the known writable settings file.
`rebuild.sh` removes stale agent backups before home-manager checks targets.
Apply the merge-reconcile pattern when another tool must write a managed file.
Do not use `force = true`, because it discards runtime-owned values.
