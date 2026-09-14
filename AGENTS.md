# AGENTS.md

This file provides guidance to AI agents (Claude Code, Codex, Antigravity, etc) when working with code in this repository.

## What This Repo Does

Personal Mac config managed with nix-darwin and home-manager. This repo is the single source of truth for the machine - the predecessor Ansible setup ([mac-dev-bootstrap](../mac-dev-bootstrap/)) is fully retired and kept only as historical reference.

## Commands

```bash
# Apply changes after editing any .nix file. THE USER RUNS THIS, NEVER THE AGENT.
rebuild                 # profile recorded in /etc/dotfiles-profile (alias for ./rebuild.sh)
rebuild work            # explicit profile; aborts on a mismatch unless --force

# Format all .nix files (nixfmt via treefmt-nix; also runs automatically on Claude edits)
nix fmt

# Validate without touching the system. --impure is required: user is derived from
# $SUDO_USER/$USER at eval time. flake check evaluates every profile (host-* checks).
nix flake check --impure --no-build
nix build --impure .#darwinConfigurations.work.system --dry-run

# Shellcheck every mkReconcile script for a host (they are only checked when built)
nix build --impure --no-link .#darwinConfigurations.work.config.home-manager.users.$USER.home.activationPackage

# Check formatting and lint in isolation
nix build --impure .#checks.aarch64-darwin.formatting
nix build --impure .#checks.aarch64-darwin.pre-commit

# Verify a profile is warning-free except the one documented upstream options.json warning
# Expected output: empty
nix eval --impure .#darwinConfigurations.work.system.drvPath 2>&1 | grep -i warning | grep -v options.json | grep -v "uncommitted changes"

# Refresh .git/hooks/pre-commit by hand (normally auto-installed by direnv on cd; see .envrc)
direnv allow && direnv exec . true

# First-time setup on a fresh machine
./bootstrap.sh work     # or: ./bootstrap.sh personal / ./bootstrap.sh work-atdj
```

New files must be `git add`ed before any nix command sees them - flake sources include tracked files only. For a read-only check of an untracked tree, use `path:.` as the flake ref.

`home/` files (Neovim, WezTerm, herdr, AI configs) are live-symlinked - editing them takes effect immediately without a rebuild. Only rebuild when changing package lists, system defaults, shell config in `.nix` files, or adding a new skill directory (Codex needs it linked).

## Architecture

```
flake.nix              - entry point; derives `user` from $SUDO_USER/$USER (impure); one
                         darwinConfiguration per hosts/*.nix (work, personal, work-atdj);
                         checks.host-<name> evaluate every profile; packages.darwin-rebuild
                         pins bootstrap's first switch to flake.lock
hosts/
  work.nix             - { system, darwin, home }  darwin imports homebrew bundles (common + work)
                         + quicklook; home imports the feature modules this host gets (zsh,
                         mise, gcloud, ai, colima, docker, gitea, langfuse, zscaler, cachepurge)
  personal.nix         - same shape; homebrew common + personal; home imports zsh, mise, gcloud,
                         ai, colima, docker, cachepurge (no gitea, no zscaler)
  work-atdj.nix        - same shape; homebrew common + work-atdj (empty scaffold for machine-
                         specific extras) + quicklook; home imports zsh, gcloud, ai, colima,
                         docker, gitea, zscaler, cachepurge (no mise, no langfuse)
modules/
  darwin/default.nix   - imports system.nix + homebrew/
  darwin/system.nix    - nix daemon handoff (Determinate), Touch ID for sudo, Rosetta,
                         /etc/dotfiles-profile marker, zsh completion/prompt handoff to hm,
                         system.defaults placeholder
  darwin/homebrew/     - default.nix: homebrew behavior (cleanup = "zap", upgrade, --force,
                         brewMaintenance + caskDequarantine activations)
                         common.nix: the audited 3-way intersection - only packages every host
                         declares; work.nix / personal.nix / work-atdj.nix: host extras
                         (add/remove a bundle = one import line in hosts/*.nix; lists auto-merge)
  darwin/quicklook.nix - feature module: QuickLook preview plugins (casks + quarantine strip /
                         registry refresh)
  home/lib/reconcile.nix - mkReconcile: the single way activation shell is written - wraps each
                         script in writeShellApplication (shellcheck gates the build, strict
                         mode, tool deps declared via `path`, atomic json_edit helper, dry-run
                         aware via home-manager's `run`)
  home/legacy.nix      - ALL one-time migration sweeps, consolidated; DELETE this file once
                         every host has run one rebuild containing it (see its header)
  home/default.nix     - core home config every host gets: Nix packages, app-config symlinks,
                         fonts; imports legacy.nix
  home/zsh.nix         - feature module: zsh + starship + direnv, zshSetup (~/.zshrc_conf dir +
                         brew-completions cache), 24h-cached compinit
  home/mise.nix        - feature module (work/personal): mise (Temurin Java 25, node,
                         terraform), miseSetup (`mise install` provisioning)
  home/gcloud.nix      - feature module: gcloud shell wiring + gcloudSetup (config/components)
  home/ai/             - feature module (directory): all AI agent config, one deliberately
                         self-contained unit per agent - default.nix (umbrella imports + the
                         shared rationale for playwrightMcp and absolute CLI paths),
                         claude/ (default.nix + langfuse.nix), codex/ (default.nix +
                         langfuse.nix), antigravity.nix, copilot.nix, opencode.nix. Each unit
                         holds that agent's symlinks, env vars, MCP, plugins, and reconcile
                         sweep; playwrightMcp is intentionally duplicated per agent - change
                         every copy. The */langfuse.nix files are TEMPORARY and deletable whole.
                         antigravity's settings.json is merge-reconciled, not symlinked, since
                         agy rewrites it at runtime - same rationale as home/docker.nix.
                         Skills: default.nix declares the one hub link ~/.agents/skills ->
                         home/ai/skills; Codex, Copilot and OpenCode read it natively (no
                         link of their own), claude/ and antigravity.nix link their skills
                         dir at the hub. Nothing touches ~/.codex/skills (Codex writes
                         .system/ there at runtime).
  home/colima.nix      - feature module (all 3 hosts): autostarts colima at login via a
                         home-manager launchd agent; no reconcile - hm owns the plist lifecycle
  home/docker.nix      - feature module (all 3 hosts): reconciles ~/.docker/config.json
                         (Keychain credentials, GCP helper, Homebrew CLI plugin discovery) via
                         an idempotent atomic jq merge - not a symlink, since Docker and gcloud
                         write into the same file at runtime
  home/gitea.nix       - feature module (work, work-atdj): local Gitea+Postgres via Docker
                         Compose (localhost-only), gitea-up/-down/-status/-logs shell functions
  home/langfuse.nix    - feature module (work only): local Langfuse stack via Docker Compose,
                         langfuse-up/-down/-status/-logs; all published ports are localhost-only
  home/zscaler.nix     - feature module (work, work-atdj): Zscaler MITM proxy wiring -
                         NODE_EXTRA_CA_CERTS, git http.sslcainfo, and trusting the cert inside
                         the colima guest VM (hash-guarded, restarts dockerd only on cert
                         rotation). The cert file (~/.ca_certs/zscalercert.pem) stays
                         user-owned, not nix-managed (public repo)
  home/cachepurge/     - feature module (all 3 hosts): default.nix wraps cache-purge.sh (plain
                         bash, shellcheck-gated) as the `cache-purge` CLI; bare = dry-run,
                         --apply reclaims now; cachePurgeAuto runs `cache-purge --auto` on every
                         rebuild, gated on free space < 100G and staleness >= 14 days; set
                         CACHE_PURGE=off to skip it (forwarded through rebuild.sh's sudo)
home/                  - actual config files symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - agent-agnostic AI config: shared AGENTS.md, skills/, per-agent settings/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; profile defaults to /etc/dotfiles-profile and a
                         mismatch aborts without --force; git pull + hm-bak preflight first
bootstrap.sh           - one-time setup: installs Determinate Nix, symlinks repo, first switch via
                         the flake's pinned darwin-rebuild, installs .git/hooks/pre-commit via direnv
docs/architecture.md   - repo layout, symlink mechanics, formatter toolchain, history
```

`flake.nix` derives the username from the environment at eval time (`$SUDO_USER` first, then `$USER`), so no login is hardcoded in the repo. Both `rebuild.sh` and `bootstrap.sh` pass `--impure` to allow this environment read.

`home/ai/AGENTS.md` is the shared agent policy file - it is symlinked to every agent's canonical location (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.copilot/copilot-instructions.md`, `~/.gemini/antigravity-cli/ANTIGRAVITY.md`). `home/ai/skills/` is exposed once, as `~/.agents/skills` (the hub, declared in `modules/home/ai/default.nix`); Codex, Copilot and OpenCode discover that path natively, while `~/.claude/skills` and `~/.gemini/antigravity-cli/skills` are directory links at the hub. Per-agent settings live under `home/ai/settings/`.

## Key Invariants (Do Not Silently Revert)

- **Never run `rebuild.sh` / `darwin-rebuild` yourself.** The user always applies the config. Stop at the static checks in "Commands" and hand over a checklist of what to verify after they rebuild. This repo is checked out on three machines and only the user knows which one they are on; `/etc/dotfiles-profile` plus `rebuild.sh`'s guard make a wrong-profile switch fail-safe, but that is a backstop, not permission.
- **All activation shell goes through `mkReconcile`** (`modules/home/lib/reconcile.nix`) - never a raw string in `home.activation`. It gates every script with shellcheck at build time (a script calling a tool missing from the hermetic activation PATH fails the build instead of silently no-oping - this exact bug shipped once in `zscaler.nix`), declares tool deps via `path`, provides atomic `json_edit`, and respects `--dry-run`. Agent CLIs are called by absolute `/opt/homebrew/bin` path for the same reason.
- **Never add `brew uninstall` loops to activation scripts** - `cleanup = "zap"` already removes every undeclared formula/cask on each switch.
- `homebrew.onActivation.cleanup = "zap"` is documented and intentional - the declared lists in `modules/darwin/homebrew/*.nix` are the single source of truth for Homebrew state. `common.nix` is the audited 3-way intersection; anything not universal is duplicated into the host bundle(s) that need it.
- **`~/.agents/skills` is the single skills hub.** Codex, Copilot and OpenCode read it natively - never re-add a per-agent skills link for them (every skill would show twice), and never point an agent's skills link at the repo path instead of the hub. Never place per-file links *inside* an agent's skills dir either: home-manager does not remove a managed symlink whose path turns into a directory, so the new links get created through the stale link - into the git checkout (see `docs/gotchas.md`). `~/.codex/skills` belongs to Codex (it writes `.system/` there).
- **The Claude model is owned by `home/ai/settings/claude.json`.** Never export `ANTHROPIC_MODEL` from nix - the env var silently overrides the settings key.
- Never commit `.no-mistakes/` validation evidence to this repo - it is gitignored.
- When disabling a config block, leave the original as a comment (not deleted) so it can be revisited later.
- When making changes that affect the user-facing workflow (new commands, bootstrap steps, package lists, gotchas), update `README.md` (keep it short - link to `docs/` for details), `docs/architecture.md`, and `docs/gotchas.md`.
- Every profile must be warning-free except for the one documented upstream `options.json` warning. Any *new* warning must be investigated and eliminated before committing.
- **This nix repo is the single source of truth for all AI-agent configuration** - plugins, skills, extensions, and MCP servers. The per-agent reconciles in `modules/home/ai/` remove any undeclared content on every rebuild. Installing via an agent CLI (`claude plugin install`, `agy plugin import`) is reverted on the next rebuild.
- Comments explain the non-obvious *why* (hermetic PATH, why a file is merge-reconciled instead of symlinked, why remove-then-add). Chronology and "confirmed via ..." notes belong in git history, not in modules.

## AI Agent Plugin Reconcile

Each agent keeps its own plugin/extension store that nix does not own, so removed config would silently persist. Per-agent reconcile activations sweep these stores on every rebuild:

| Agent (module)    | Mechanism                                                                                                            | Keep-set                                                      |
|-------------------|----------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| Claude (`ai/claude/default.nix`, `claudeReconcile`) | Keep-set prune of `installed_plugins.json` + `known_marketplaces.json` + `marketplaces`/`cache` dirs; `claude mcp remove` for undeclared MCP | playwright MCP + whatever `home/ai/settings/claude.json` lists under `enabledPlugins` / `extraKnownMarketplaces` (read at eval time). Install of the langfuse plugin: `ai/claude/langfuse.nix` (TEMPORARY) |
| Codex (`ai/codex/default.nix`, `codexReconcile`) | Stale-backup sweep only; MCP via `codex mcp add` remove-then-add; langfuse tracing plugin installed by `ai/codex/langfuse.nix` (TEMPORARY) | (no plugin prune wired yet - codex has no list-and-prune) |
| Gemini CLI (`ai/antigravity.nix`, `antigravityReconcile`) | Remove all dirs under `~/.gemini/extensions/`; reset `extension-enablement.json -> {}`                               | (none - gemini extensions are the root import source for agy) |
| Antigravity (agy) (`ai/antigravity.nix`, `antigravityReconcile`) | Sweep `~/.gemini/antigravity-cli/plugins/*`; reset `import_manifest.json`                                            | playwright (nix symlink declared in `home.file`)              |
| Copilot (`ai/copilot.nix`, `copilotReconcile`) | `rm -rf ~/.copilot/installed-plugins`; clear `installedPlugins` in `config.json`                                     | (none)                                                        |

The gemini extension removal is the critical step: extensions installed there are auto-imported into antigravity on `agy` startup, so removing only the antigravity copy lets them re-appear.

Stale `.hm-bak` files and agent-created dated backups (`settings.json.YYYYMMDD`) are also cleaned per agent dir by each reconcile. That alone cannot unblock a stale `settings.json.hm-bak` that home-manager's `checkLinkTargets` trips over *before* any activation runs, so `rebuild.sh` runs a preflight `*.hm-bak` sweep under all agent config dirs (this is also why antigravity's settings.json is merge-reconciled instead of symlinked).

## Known Upstream Warning

Every rebuild emits this warning:
```
warning: Using 'builtins.derivation' to create a derivation named 'options.json'
that references the store path '/nix/store/...-source' without a proper context.
```
**This is harmless** - the build succeeds. It is an upstream nixpkgs bug in `nixos/lib/make-options-doc`, surfaced by home-manager's man-page generation. Tracking: [nixpkgs#485682](https://github.com/NixOS/nixpkgs/issues/485682), [home-manager#7935](https://github.com/nix-community/home-manager/issues/7935).

**Workaround (if you want zero warnings):** add `manual.manpages.enable = false;` to `modules/home/default.nix`. Currently left enabled intentionally - revisit once nixpkgs ships a fix.
