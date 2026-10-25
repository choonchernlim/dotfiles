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

**The Claude `reviewer` subagent's model can be silently overridden.**
`model: opus` in `home/ai/agents/claude/reviewer.md` beats the
`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` that `home/ai/settings/claude.json` sets,
unless `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is also set. `CLAUDE_CODE_EFFORT_LEVEL`
beats its `effort: high`. Setting either of those two variables downgrades every
review pass, and so does a `model` passed on the spawn call.

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `codex plugin add`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild`. To keep a plugin, declare it in nix - for Claude that means `enabledPlugins`/`extraKnownMarketplaces` in `home/ai/settings/claude.json`, which the reconcile reads as its keep-set. See [AI Agent Plugin Reconcile](architecture.md#ai-agent-plugin-reconcile) for details.

**Skills live in one hub: `~/.agents/skills`.**
The [architecture guide](architecture.md#how-symlinks-work) owns the link
layout. Never add another Codex, Copilot, or OpenCode skills link because it
would list each skill twice.

Skills are authored in the separate skills repo, which `sync-skills.sh` checks
out beside this one. The hub links into that checkout, so skill edits and new
skill directories are live without rebuilding. `rebuild` pulls the checkout only
when it is on `main`, so a skill developed on a branch is left alone. A conflicting
pull is recovered the same way as the dotfiles pull: backup branch, then reset to upstream.

**An empty `~/.agents/skills` means the skills checkout is missing.**
home-manager links the hub without checking its target. A switch that bypassed
`sync-skills.sh` leaves every agent without skills, and the `skillsHubCheck`
activation prints a warning. Run `rebuild` again. This happens once on each
machine whose `rebuild` pulled the skills-repo change, because that run was
still executing the previous `rebuild.sh`.

**`rebuild` runs the logic from the tree as it was before the pull.**
The `rebuild.sh` shim builds `scripts/rebuild/` with `nix run` first, then the
command pulls the repo. A change to the rebuild logic itself therefore takes
effect on the run after the one that pulled it; `darwin-rebuild` still evaluates
the post-pull flake. A new file under `scripts/rebuild/` must be `git add`ed
before it is visible to `nix run`.

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
It installs for Claude, Codex, Copilot, OpenCode, and Antigravity. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions. Keep it agent-neutral: name Claude-only slash commands (e.g. `/simplify`) as examples next to a generic step, never as the only instruction.

**The shared Claude model is set only in `home/ai/settings/claude.json`.**
Per-host exceptions go through `dotfiles.claude.model` in `hosts/<name>.nix` (the `personal` host sets `opus`), which appends `--model` to the `claude` zsh alias - never edit the shared file per host, it is a live symlink every host reads. The flag only reaches shell launches: IDE extensions and anything exec'ing the binary directly still get the settings value.
`ANTHROPIC_MODEL` is deliberately not exported by nix: the env var overrides the settings `model` key and used to make that key dead. If `/model` reports an env override, something outside this repo is setting it.

**The shell setup is deliberately minimal.**
Nixpkgs supplies autosuggestions and highlighting, while Starship supplies the
prompt. The retained aliases are `rebuild`, `personal_claude`, and the
Langfuse wrappers. Mise replaces nvm and sdkman.

**`rebuild` reports a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See "Every rebuild emits one `options.json` warning" below for details and the one-line workaround.

**`rebuild` auto-syncs the repo before applying.** `rebuild.sh` runs `git pull --rebase --autostash` when on `main` (skipped with a notice on any other branch) so a machine always applies the latest committed config. Autostash means uncommitted edits survive the pull. If the pull conflicts, `scripts/git-sync.sh` saves everything local (unpushed commits, uncommitted and untracked files) to a `rebuild-backup/<timestamp>` branch, then hard-resets to upstream so the rebuild applies the remote's state instead of blocking. Recover with `git log rebuild-backup/<timestamp>` and `git checkout rebuild-backup/<timestamp> -- <path>` or `git cherry-pick`. If the fetch itself fails (offline, no access) there is nothing to reset to, so the rebuild aborts.

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
invariant above still bites. Before a rebuild, `scripts/check-warnings.sh` (also
run in CI) fails on the same unknown warnings, and the `host-<name>` flake checks
fail on module warnings.

**An inline `home-manager.sharedModules` module needs `_file`.**
Without it, its `home.activation` entries look defined by home-manager itself, so
the `activation` flake check skips them and a raw activation string there goes
unnoticed. `modules/darwin/homebrew/default.nix` and `modules/darwin/quicklook.nix`
set `_file = ./<this file>;` for this reason.

**`rebuild` output goes through a formatter.**
`rebuild.sh` tees the raw stream to `~/.cache/dotfiles/rebuild-<timestamp>.log`
and pipes it through `rebuild-format` (`scripts/rebuild/`), so the summary is grouped and
short. Because the stream is piped, Nix's live progress bar is gone; the
formatter draws a `⏳ <phase>  <elapsed>` status line in its place, paused during
the sync and homebrew phases so it never erases a `sudo` password prompt (a cask
upgrade can ask for one). Homebrew lists each upgrade or install as it starts
instead of a timer. `rebuild -v` prints the raw stream instead. On failure the last 40 raw lines and the log path are
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

**Install herdr plugins through `modules/home/herdr.nix`, not `herdr plugin install`.**
The plugin checkouts and `plugins.json` land in the gitignored part of
`home/.config/herdr/` (`~/.config/herdr` is a symlink into this repo), so a
hand install exists on one host only. Add the plugin to the `plugins` list
instead (with its plugin `id`); every rebuild installs the pinned commit and
enables it. A failed install or a missing `/opt/homebrew/bin/herdr` does not fail
the rebuild but prints a `herdr-plugins-setup:` line on stderr, so check the
rebuild output on a host where a plugin is missing. herdr records absolute paths,
so after a move (such as the dev root move) `herdr plugin list` warns `manifest
unavailable`; the next rebuild reinstalls or relinks the affected plugins. The
rebuild also uninstalls or unlinks every plugin that is not declared, so a hand
install is removed on the next rebuild. Local plugins under
`home/herdr-plugins/` are linked (`herdr plugin link`), not installed: every
subdirectory with a `herdr-plugin.toml` is linked under its manifest `id`. A
local manifest is snapshotted into
`plugins.json` at link time, so bump its `version` after editing it (see
[architecture](architecture.md)). The `worktreeinclude` hook runs in the background, so a very large include set may still be copying
when an agent starts; `herdr plugin log list --plugin dotfiles.worktreeinclude`
shows what it copied.

**reviewr's own auto-open skips plain workspaces and a repo's main space.**
`reviewr-autoopen` fills that gap, but only for workspaces created after it is
linked: in an older workspace without the pane, run the `reviewr: open pane`
action once. It always splits right and ignores reviewr's `toggle_placement`,
`toggle_direction`, and `auto_open` settings, so change the hook if you change
those. `herdr plugin log list --plugin dotfiles.reviewr-autoopen` shows what it
opened.

**Re-running `herdr integration install` breaks the committed hooks.**
It rewrites `settings/claude.json` and `settings/copilot.json` with a single-quoted
`'~/...'` path, which bash never expands (exit 127, so the hook silently never
runs). The `hook-paths` flake check fails on it. Restore `bash "$HOME/..."` and
review the diff of the vendored script under `home/ai/hooks/`. The rest of `home/.config/herdr/` is runtime state and stays
ignored.

**herdr worktrees need their own mise trust root.**
herdr checks out worktrees under `~/.herdr/worktrees/<repo>/<name>`, outside
`~/Developer`, so mise prompts `mise trust` for each new worktree's
`.mise.toml`. `home/.config/mise/config.toml` lists `~/.herdr/worktrees` in
`trusted_config_paths` (live, no rebuild; `~` expands per user, so every host
that has mise and herdr gets it).

**Keep checkouts out of `~/Documents`, `~/Desktop`, and `~/Downloads`.**
macOS privacy protection (TCC) grants these folders per app. A process
detached from the terminal, such as the herdr server, is checked as itself
rather than as WezTerm, so it and every pane it starts get `Operation not
permitted` on any path that resolves into them. That includes the
live-symlinked configs: the mise and starship configs resolve through
`~/.dotfiles` into the checkout. A Full Disk Access grant for herdr is not a
fix, because Homebrew's ad-hoc-signed binary lands at a new path with a new
signature on every upgrade. Code lives in `~/Developer`.

**WezTerm Option+Left/Right types `;3D` instead of jumping a word.**
WezTerm encodes Option+arrow as xterm `ESC[1;3D`/`ESC[1;3C`, which zsh and
most line editors leave unbound, so the tail lands as literal text.
`home/.config/wezterm/wezterm.lua` rebinds them with `SendKey` to Alt-b/Alt-f
(live, no rebuild), the word jump every readline-style editor binds, matching
Terminal.app. Cmd+Left/Right (line start/end in IDEs) is unbound in WezTerm, so
the same file sends Ctrl-a/Ctrl-e, like iTerm2's "Natural Text Editing". Fix
these there rather than with a zsh `bindkey`, which would cover only the shell
prompt.

**VS Code's terminal shows prompt icons as boxes unless it uses a Nerd Font.**
Its default font (Menlo) lacks the starship glyphs; VS Code draws only the
powerline arrows itself. `home/vscode/settings.json` sets
`terminal.integrated.fontFamily` to Hack Nerd Font, like WezTerm. It is
live-linked to `~/Library/Application Support/Code/User/settings.json`, so
settings changed in VS Code's UI land in the repo; `keybindings.json` is linked
the same way. The first rebuild on a host that already has either file (or a
`~/Library/Application Support/biome/biome.json`) moves it to `<name>.hm-bak`;
merge anything worth keeping into the repo copy.

**VS Code extensions are nix-managed too.**
`modules/home/vscode.nix` installs the `dotfiles.vscode.extensions` list and
uninstalls everything else on each `rebuild`, so an extension installed from
the VS Code UI is gone next time. Declare it in the base list, or for one host
in `hosts/<host>.nix` (`dotfiles.vscode.extensions = [ "publisher.name" ];`).
Pylance is deliberately absent: ty is the Python language server. Installing
`ms-python.python` pulls Pylance in through its extension pack, and the same
reconcile removes it.

**VS Code extension installs need the Zscaler CA exported by the reconcile.**
`code` is node, and the hermetic activation env lacks the `NODE_EXTRA_CA_CERTS`
session variable, so behind Zscaler every marketplace call during `rebuild` fails
with "unable to get local issuer certificate". `vscode.nix` therefore exports it
itself, taking the path from `home.sessionVariables.NODE_EXTRA_CA_CERTS` (set in
`zscaler.nix`); renaming that variable silently drops the export.

**Never add a SAS connection profile from the user-level command.**
Like any UI change (above), it lands in the published repo copy, here with the
SAS server's host and user. Put `SAS.connectionProfiles` in the SAS project's
`.vscode/settings.json` instead. SSH key auth needs `SSH_AUTH_SOCK` and the
key loaded with `ssh-add`.

**Biome formats JS/TS in every repo, not only Biome ones.**
It is the global default formatter. A repo without its own Biome config uses
the fallback `home/biome/biome.json`, linked to
`~/Library/Application Support/biome/`; Biome's built-in default would indent
with tabs. The fallback always indents with spaces (it overrides a root
`.editorconfig`'s `indent_style`) and takes indent size, line endings, and the
final newline from that `.editorconfig`. A Prettier repo sets
`"editor.defaultFormatter": "esbenp.prettier-vscode"` in its
`.vscode/settings.json`. ESLint repos show Biome's diagnostics next to
ESLint's.

**Dev root move: `~/Documents/development` to `~/Developer`.**
On each host, quit agents and IDEs, then:

```sh
herdr server stop
mv ~/Documents/development ~/Developer
~/Developer/github/dotfiles/rebuild.sh <profile>
```

Run the first rebuild by full path: the `rebuild` alias resolves through
`~/.dotfiles`, which dangles until `rebuild.sh` re-points it (and
`sync-skills.sh` re-points `~/.dotfiles-skills`). The `devRootMigration`
activation in `modules/home/legacy.nix` then rewrites the path-keyed state:
`~/.gitconfig` `includeIf` conditions, Claude Code projects, prompt history and
per-project memory folders, Codex `config.toml` tables, git worktree links, and
direnv approvals (only those that still match the `.envrc` content). Each step
shows as a `devroot` row in the rebuild summary; a `⚠ devroot` row means the
move is pending or both roots exist. Not migrated: herdr workspaces (the
running server overwrites `session.json`; recreate them) and IDE recent
projects (reopen from the new path). Once every host has moved, delete
`devRootMigration` and drop `~/Documents/development` from the mise
`trusted_config_paths`.

**The repo devShell must stay `mkShellNoCC`.**
The default `mkShell` stdenv exports `DEVELOPER_DIR` and `SDKROOT` at a nix
apple-sdk and puts xcbuild's `xcrun` first on `PATH`. direnv carries that into
everything started in this directory (herdr panes, agents), where `/usr/bin/git`,
an `xcrun` shim, then fails with `error: tool 'git' not found`. After changing
the devShell, run `direnv reload` and open a new pane; existing processes keep
the old environment.

**Colima's disk is sparse and grows until trimmed; ClickHouse system logs were the bulk.**
`~/.colima/_lima/_disks/colima/datadisk` only grows on the Mac; freed space inside
the VM returns to macOS after `fstrim` (the guest has a weekly `fstrim.timer`).
ClickHouse keeps its own telemetry tables (`system.trace_log`, `text_log`, ...)
forever by default; they reached ~17G against ~175M of real Langfuse data, so
`clickhouse-logs.xml` removes them. Log sections the image does not know are
ignored, so re-check with `SELECT name FROM system.tables WHERE name LIKE '%_log'`
after an image upgrade. The override only stops new writes. Its bind-mount source is the repo
checkout via `~/.dotfiles`, never a `~/.config` link: those resolve into `/nix/store`,
which the colima VM cannot see, and dockerd fails with `mkdir ...: file exists`.
One-time cleanup: drop existing tables by hand (`DROP TABLE system.trace_log SYNC`),
truncate the old files in the `langfuse_clickhouse_logs` volume, then
`docker builder prune -a` and `colima ssh -- sudo fstrim -av`. `docker image prune -a`
also frees space but forces re-pulls through the Zscaler proxy. Shrinking the disk
itself needs `colima delete --data`, which wipes the gitea and langfuse volumes.
`colima.nix` runs two launchd agents (logs in `~/Library/Logs/colima.prune*.log`).
Weekly (Sunday 03:00) it prunes build cache, dangling images and stopped
containers older than 7 days, then fstrims. Monthly (1st, 04:00) it also runs
`image prune -a` for images unused for 30 days, which are re-pulled through the
Zscaler proxy when needed. Volumes are never touched.
