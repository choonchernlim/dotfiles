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
Anything installed outside this repo (via `claude plugin install`, `codex plugin add`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild`. To keep a plugin, declare it in nix - for Claude that means `enabledPlugins`/`extraKnownMarketplaces` in `home/ai/settings/claude.json`, which the reconcile reads as its keep-set. See [AI Agent Plugin Reconcile](architecture.md#ai-agent-plugin-reconcile) for details.

**Skills live in one hub: `~/.agents/skills`.**
The [architecture guide](architecture.md#how-symlinks-work) owns the link
layout. Never add another Codex, Copilot, or OpenCode skills link because it
would list each skill twice.

Skills are authored in the separate skills repo, which `sync-skills.sh` checks
out beside this one. The hub links into that checkout, so skill edits and new
skill directories are live without rebuilding. `rebuild` pulls the checkout only
when it is on `main`, so a skill developed on a branch is left alone.

**An empty `~/.agents/skills` means the skills checkout is missing.**
home-manager links the hub without checking its target. A switch that bypassed
`sync-skills.sh` leaves every agent without skills, and the `skillsHubCheck`
activation prints a warning. Run `rebuild` again. This happens once on each
machine whose `rebuild` pulled the skills-repo change, because that run was
still executing the previous `rebuild.sh`.

Codex owns
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

**`rebuild` reports a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See "Every rebuild emits one `options.json` warning" below for details and the one-line workaround.

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

**Every rebuild emits one `options.json` warning.**
`warning: Using 'builtins.derivation' to create a derivation named 'options.json' that references the store path '/nix/store/...-source' without a proper context.`
This is harmless and the build succeeds. It is an upstream nixpkgs bug in
`nixos/lib/make-options-doc`, surfaced by home-manager's man-page generation
([nixpkgs#485682](https://github.com/NixOS/nixpkgs/issues/485682),
[home-manager#7935](https://github.com/nix-community/home-manager/issues/7935)).
Adding `manual.manpages.enable = false;` to `modules/home/default.nix` silences
it; that is intentionally not done, pending an upstream fix. Every *other*
warning is a real regression - investigate it before committing.

The `rebuild` summary shows it as one line, `⚠ 1 known warning: options.json
(upstream)`, and the full text stays in the log. Any other warning prints in full
under an "unknown warning - investigate before committing" note, so the
invariant above still bites.

**`rebuild` output goes through a formatter.**
`rebuild.sh` tees the raw stream to `~/.cache/dotfiles/rebuild-<timestamp>.log`
and pipes it through `scripts/rebuild-format.sh`, so the summary is grouped and
short. Because the stream is piped, Nix's live progress bar is gone; the
formatter draws a `⏳ <phase>  <elapsed>` status line in its place, paused during
the sync phase so it never erases the `sudo` password prompt. `rebuild -v` prints
the raw stream instead. On failure the last 40 raw lines and the log path are
printed. See [Rebuild Output](architecture.md#rebuild-output).

Any background process the inner run starts must detach its stdio
(`>/dev/null 2>&1 &`), as the `sudo` keepalive loop does. Otherwise it inherits
the pipe, the formatter never sees end of input, and `rebuild` hangs after the
switch finishes.

**Homebrew variables for `brew bundle` go in `homebrew.onActivation.extraEnv`.**
`environment.variables` never reaches the bundle run: nix-darwin starts the
activation script under `env -i` and then runs `brew` through
`sudo --preserve-env=PATH`. It only covers interactive `brew`, so the hint,
analytics, and new-casks blocks kept printing on every rebuild until the same
variables were also set in `extraEnv`.
