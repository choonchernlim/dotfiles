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
  work-atdj.nix        - same shape; common homebrew bundle + an empty work-atdj extras bundle;
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
  ai/                  - shared AGENTS.md, skills/, per-agent settings/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; profile defaults to /etc/dotfiles-profile and a
                         mismatch aborts without --force
bootstrap.sh           - one-time setup: Nix, symlink, first switch (pinned darwin-rebuild), git hooks
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

`home/ai/skills/` is exposed once as `~/.agents/skills` by
`modules/home/ai/default.nix`. Codex, Copilot, and OpenCode discover that
hub natively. Claude Code and Antigravity receive their own directory links
to the hub.

A new skill directory becomes live without a rebuild. Nix never touches
`~/.codex/skills`, where Codex writes bundled system skills. Per-agent
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

The Claude repo hook (`.claude/settings.json`) auto-formats `*.nix` files on every Claude edit via a PostToolUse hook. It gracefully no-ops if nixfmt is not yet on PATH (pre-`rebuild`).

## History

This repository replaced the retired
[Ansible setup](../../mac-dev-bootstrap/). Each capability moved to a Nix
feature or was removed. `modules/home/legacy.nix` owns the remaining
one-time sweeps.

The remaining migration follow-up is the deliberate design of
`system.defaults`. Its placeholder stays commented in
`modules/darwin/system.nix`.
