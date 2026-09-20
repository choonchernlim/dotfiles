<!--
Purpose: Explains how profiles, modules, mutable state, and checks fit together.
Type: explanation
-->

# Architecture

Audience: maintainers deciding where a dotfiles change belongs.

## Table of Contents

- [Repository Layout](#repository-layout)
- [How Symlinks Work](#how-symlinks-work)
- [Docker Toolchain](#docker-toolchain)
- [Formatter and Linters](#formatter-and-linters)
- [AI Agent Plugin Reconcile](#ai-agent-plugin-reconcile)
- [History](#history)

## Repository Layout

```text
flake.nix              - entry point; derives user from $SUDO_USER/$USER (impure); one
                         darwinConfiguration per hosts/*.nix; host-<name> checks evaluate
                         every profile; packages.darwin-rebuild pins bootstrap's first switch
hosts/
  work.nix             - { system, darwin, home } - darwin imports homebrew bundles + quicklook;
                         home imports the feature modules this host gets
  personal.nix         - same shape
  work-atdj.nix        - same shape; common homebrew bundle + the work-atdj extras bundle
                         (Claude desktop app and Claude Code CLI);
                         home modules zsh/gcloud/ai/colima/docker/gitea/zscaler/cachepurge
                         (no mise, no langfuse)
modules/
  darwin/default.nix   - imports system.nix + homebrew/
  darwin/system.nix    - nix daemon handoff, Touch ID for sudo, Rosetta, the /etc/dotfiles-profile
                         marker rebuild.sh checks, zsh completion/prompt handoff to home-manager
  darwin/homebrew/     - default.nix: homebrew behavior (zap cleanup, upgrades, --force, brew
                         maintenance + cask dequarantine activations)
                         common.nix: the audited 3-way intersection - only packages every host
                         declares; work.nix / personal.nix / work-atdj.nix: host extras
                         (hosts pick bundles by import; lists auto-merge)
  darwin/quicklook.nix - feature: QuickLook preview plugins (casks + quarantine strip/refresh)
  home/lib/reconcile.nix - mkReconcile: the single way activation shell is written - wraps
                         scripts in writeShellApplication (shellcheck at build time, strict
                         mode, declared tool deps on PATH, atomic json_edit, dry-run aware)
  home/legacy.nix      - one-time migration sweeps; DELETE once every host has run a rebuild
                         containing it (see file header)
  home/default.nix     - core home config every host gets: packages, app symlinks, fonts;
                         imports legacy.nix
  home/zsh.nix         - feature: zsh + starship + direnv (+ zshSetup: ~/.zshrc_conf dir,
                         brew-completions cache)
  home/mise.nix        - feature (work/personal): mise tool versions (+ miseSetup)
  home/gcloud.nix      - feature: gcloud shell wiring, config, components (+ gcloudSetup)
  home/ai/             - feature (directory): AI agent config, one self-contained unit per agent
      default.nix      - umbrella imports, the ~/.agents/skills hub link, and the shared
                         rationale (playwrightMcp, absolute paths)
      claude/          - default.nix (symlinks, MCP, reconcile) + langfuse.nix (TEMPORARY plugin
                         install and CC_LANGFUSE_TAGS patch)
      codex/           - default.nix (config.toml upsert, MCP, backup sweep; no skills link -
                         Codex reads the hub natively and owns ~/.codex/skills)
                         + langfuse.nix (TEMPORARY tracing plugin install)
      antigravity.nix  - symlinks, playwright plugin, settings merge-reconcile, agy update,
                         sweep of both agy's plugin store and ~/.gemini/extensions
      copilot.nix      - symlinks, MCP config, plugin-store reset
      opencode.nix     - symlinks, opencode.json (MCP)
  home/colima.nix      - feature (all 3 hosts): autostarts colima at login via a launchd agent
  home/docker.nix      - feature (all 3 hosts): reconciles Docker credentials and Homebrew
                         CLI plugin discovery via an atomic jq merge, not a symlink
  home/gitea.nix       - feature (work, work-atdj): local Gitea+Postgres via Docker Compose,
                         gitea-up/-down/-status/-logs shell functions
  home/langfuse.nix    - feature (work only): local Langfuse stack via Docker Compose,
                         langfuse-up/-down/-status/-logs shell functions
  home/zscaler.nix     - feature (work, work-atdj): Zscaler MITM cert wiring - NODE_EXTRA_CA_CERTS,
                         git http.sslcainfo, colima guest VM trust; the cert file itself stays
                         user-owned, not nix-managed (public repo)
  home/cachepurge/     - feature (all 3 hosts): default.nix wraps cache-purge.sh (plain bash,
                         shellcheck-gated) as the `cache-purge` command + the auto activation
home/                  - config files live-symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - shared AGENTS.md, per-agent settings/ (skills live in the skills repo)
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; profile defaults to /etc/dotfiles-profile and a
                         mismatch aborts without --force
bootstrap.sh           - one-time setup: Nix, symlink, skills checkout, first switch (pinned
                         darwin-rebuild), git hooks
sync-skills.sh         - clones or pulls the skills repo beside this checkout and links it to
                         ~/.dotfiles-skills; run by rebuild.sh and bootstrap.sh before the switch
docs/                  - extended documentation (you are here)
```

Hosts select feature modules through imports such as Homebrew bundles.
Permanent reconciles live beside their feature through `mkReconcile`.
One-time migration sweeps live in `legacy.nix`.

Homebrew `cleanup = "zap"` removes retired packages. Activation shell never
uninstalls them. A `TEMPORARY` file is designed for whole-file removal.

## How Symlinks Work

`mkOutOfStoreSymlink` points config paths directly at this repo via `~/.dotfiles`, so edits to files under `home/` are immediately live - no rebuild needed. Only run `rebuild` when changing a `.nix` file.

`home/ai/AGENTS.md` is symlinked to every AI agent's canonical location:

| Target path                                | Agent       |
|--------------------------------------------|-------------|
| `~/.claude/CLAUDE.md`                      | Claude Code |
| `~/.codex/AGENTS.md`                       | Codex       |
| `~/.config/opencode/AGENTS.md`             | opencode    |
| `~/.copilot/copilot-instructions.md`       | Copilot     |
| `~/.gemini/antigravity-cli/ANTIGRAVITY.md` | Antigravity |

Skills live in the separate [skills repo](https://github.com/choonchernlim/skills),
checked out beside this one. `sync-skills.sh` clones it when missing, pulls it
when it is on `main`, and points `~/.dotfiles-skills` at it. `rebuild.sh` and
`bootstrap.sh` run it before every switch.

`modules/home/ai/default.nix` exposes `~/.dotfiles-skills/skills` once as
`~/.agents/skills`. Codex, Copilot, and OpenCode discover that hub natively.
Claude Code and Antigravity receive their own directory links to the hub.

| Choice | Reason |
| --- | --- |
| Live checkout, not a flake input | Agents write `.trash/` and `synced/` through the hub, and a store path is read-only. Skill edits also stay live. |
| Sync in the scripts, not in activation | The hermetic activation PATH has no ssh, and the clone reuses the auth that fetched this repo. |
| Clone URL derived from this repo's origin | The protocol that fetched the dotfiles fetches the skills. `SKILLS_REPO` overrides it. |

A skill edit or a new skill directory is live without a rebuild. Nix never
touches `~/.codex/skills`, where Codex writes bundled system skills. Per-agent
settings live under `home/ai/settings/`.

## Docker Toolchain

Every profile installs Colima, the Docker CLI, Buildx, Compose, and the
Keychain credential helper from the common Homebrew bundle. Colima supplies
the Docker engine without requiring Docker Desktop.

`modules/home/docker.nix` merges settings into Docker's writable
`~/.docker/config.json`. It preserves runtime additions while declaring
Keychain credentials, the GCP helper, and Homebrew's CLI plugin directory.

## Formatter and Linters

The repo uses treefmt-nix (nixfmt) for formatting and git-hooks.nix for pre-commit enforcement.

```sh
nix fmt                                               # format all .nix files
nix build --impure .#checks.aarch64-darwin.formatting # formatting gate (CI-style)
nix build --impure .#checks.aarch64-darwin.pre-commit # lint gate (statix + deadnix)
nix flake check --impure --no-build                   # + evaluates every host profile
direnv allow && direnv exec . true                    # install .git/hooks/pre-commit by hand
```

Direnv refreshes the pre-commit hook through `.envrc` whenever the repository
is entered. The hook runs nixfmt, statix, and deadnix. Its binaries come from
Nix store paths rather than the ambient `PATH`.

`nix develop` alone creates a transient garbage-collection root. Nix-direnv
creates a persistent root under `.direnv/` after `direnv allow`, which
keeps the hook closure available.

Activation scripts receive the same treatment. `mkReconcile` wraps each one
in `writeShellApplication`, so shellcheck rejects undeclared tool
dependencies while building.

Claude Code (`.claude/settings.json`) and Codex (`.codex/hooks.json`) declare the
same PostToolUse hook. It runs `scripts/format-hook.sh`, which auto-formats the
`*.nix` files an edit touched: it reads Claude's `file_path` and the file headers
of a Codex `apply_patch`. It gracefully no-ops if nixfmt is not yet on PATH
(pre-`rebuild`). The `agent-hooks` flake check fails evaluation when the two hook
blocks drift apart. Codex runs project hooks only after the project is trusted.

Both agents also cap the size of one tool output: `bashOutputMaxChars` in
`.claude/settings.json` and `tool_output_token_limit` in `.codex/config.toml`.
The root `.ignore` keeps `flake.lock` out of ripgrep-based agent search, which
the Read deny alone does not; `rg -u` overrides it.

## AI Agent Plugin Reconcile

Each agent keeps a plugin or extension store that nix does not own, so removed
config would silently persist. A per-agent reconcile activation sweeps each
store on every rebuild.

| Agent | Module | Sweep | Keep-set |
| --- | --- | --- | --- |
| Claude Code | `ai/claude/default.nix` | Keep-set prune of `installed_plugins.json`, `known_marketplaces.json`, and the `marketplaces`/`cache` dirs; `claude mcp remove` for undeclared MCP | playwright MCP, plus whatever `home/ai/settings/claude.json` lists under `enabledPlugins` and `extraKnownMarketplaces` (read at eval time) |
| Codex | `ai/codex/default.nix` | Stale-backup sweep only; MCP via `codex mcp add` remove-then-add | none - Codex has no list-and-prune |
| Gemini CLI | `ai/antigravity.nix` | Remove every dir under `~/.gemini/extensions/`; reset `extension-enablement.json` to `{}` | none |
| Antigravity (agy) | `ai/antigravity.nix` | Sweep `~/.gemini/antigravity-cli/plugins/*`; reset `import_manifest.json` | playwright, declared as a nix symlink in `home.file` |
| Copilot | `ai/copilot.nix` | `rm -rf ~/.copilot/installed-plugins`; clear `installedPlugins` in `config.json` | none |

Removing the Gemini CLI extensions is the critical step. Extensions installed
there are auto-imported into Antigravity when `agy` starts, so removing only
the Antigravity copy lets them re-appear.

The langfuse plugin installs live in `ai/claude/langfuse.nix` and
`ai/codex/langfuse.nix`. Both are `TEMPORARY` files, designed for whole-file
removal.

Each reconcile also cleans stale `.hm-bak` files and agent-written dated
backups (`settings.json.YYYYMMDD`) in its agent dir. That cannot unblock a
stale `settings.json.hm-bak`, which home-manager's `checkLinkTargets` trips
over before any activation runs, so `rebuild.sh` sweeps `*.hm-bak` under every
agent config dir first. That ordering is also why Antigravity's
`settings.json` is merge-reconciled instead of symlinked.

## History

This repository replaced the retired
[Ansible setup](../../mac-dev-bootstrap/). Each capability moved to a Nix
feature or was removed. `modules/home/legacy.nix` owns the remaining
one-time sweeps.

The remaining migration follow-up is the deliberate design of
`system.defaults`. Its placeholder stays commented in
`modules/darwin/system.nix`.
