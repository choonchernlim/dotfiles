<!--
Purpose: Entry point for the managed Mac setup, its profiles, commands, and guides.
Type: readme-project
-->

# Dotfiles

Personal Mac configuration managed with nix-darwin and home-manager.

## Table of Contents

- [Introduction](#introduction)
- [Profiles](#profiles)
- [Getting Started](#getting-started)
- [Resources](#resources)

## Introduction

This repository is the source of truth for three Apple Silicon Mac profiles.
It installs tools, reconciles mutable configuration, and links editable files.

| Area | Managed Behavior |
| --- | --- |
| macOS | Settings, Touch ID for sudo, fonts, and QuickLook plugins |
| Shell | zsh, Starship, completions, and syntax assistance |
| Toolchains | mise with Java, Node.js, and Terraform |
| Cloud | gcloud configuration and components |
| Developer tools | Neovim, ripgrep, fd, fzf, jq, lazygit, and Git tooling |
| AI agents | Shared policy, skills, plugins, MCP servers, and tracing |
| Containers | Colima with Homebrew-managed Docker, Buildx, and Compose plugins |
| Local services | Gitea and Langfuse through Docker Compose |
| Credentials | Keychain registry storage and the GCP Artifact Registry helper |
| Corporate network | Host and Colima trust for the Zscaler certificate |
| Maintenance | Formatting, pre-commit checks, and automatic cache cleanup |

## Profiles

Every profile shares a common base: macOS defaults, Homebrew, zsh, gcloud, AI agents, colima, docker, QuickLook, cache-purge. Each adds a bit more on top:

| Profile     | Adds beyond the common base               |
|-------------|-------------------------------------------|
| `work`      | mise, gitea, Langfuse, Zscaler cert trust |
| `personal`  | mise                                      |
| `work-atdj` | gitea, Zscaler cert trust (no mise)       |

See [docs/architecture.md](docs/architecture.md) for the full per-host module breakdown.

## Getting Started

### Prerequisites

- Apple Silicon Mac (Intel: set `system = "x86_64-darwin"` in `hosts/<profile>.nix`)
- Nothing else - `bootstrap.sh` installs Nix

### Installation

```sh
git clone https://github.com/choonchernlim/dotfiles.git
cd dotfiles
./bootstrap.sh work       # or: ./bootstrap.sh personal / ./bootstrap.sh work-atdj
```

`bootstrap.sh` does five things in order:
1. Installs Determinate Nix (skips if already installed)
2. Symlinks this repo to `~/.dotfiles` (required before the first build)
3. Clones the [skills repo](https://github.com/choonchernlim/skills) beside this one and symlinks it to `~/.dotfiles-skills`
4. Runs the first `darwin-rebuild switch` using the nix-darwin revision pinned in `flake.lock`
5. Installs the git pre-commit hooks via direnv (`.envrc` runs `use flake . --impure`)

The switch records the profile in `/etc/dotfiles-profile`. Use `rebuild` for
later changes. In a new terminal, direnv requests one `direnv allow` after
the first `cd` into the repository. This protects the hook's Nix store
closure from garbage collection.

On a fresh work host, create the local service containers once:

```sh
gitea-up
langfuse-up
```

### Verification

```sh
nix flake check --impure --no-build   # evaluates every profile, not just this machine's
nix build --impure .#darwinConfigurations.work.system --dry-run
```

### Daily Use

```sh
rebuild         # apply changes to this machine's recorded profile (alias for ./rebuild.sh)
rebuild work    # same, and errors out if this machine is recorded as a different profile
nix fmt         # format all .nix files (also fires automatically on Claude and Codex edits)
```

Only run `rebuild` when changing a package list, system default, or `.nix` config. Editing files under `home/` takes effect immediately - they're live-symlinked into place.

Agent skills live in the separate [skills repo](https://github.com/choonchernlim/skills). `rebuild` clones it beside this checkout, or pulls its latest commit, and serves it live as `~/.agents/skills`. Edit and commit skills there.

The [rebuild safety rules](docs/gotchas.md) cover profile checks, repository
synchronization, and stale agent backups.

## Resources

| Resource | What It Answers |
| --- | --- |
| [Architecture](docs/architecture.md) | How profiles, modules, links, Docker plugins, and checks fit together |
| [Gotchas](docs/gotchas.md) | Which runtime-written files and lifecycle behaviors need care |
| [Implementation guardrails](docs/implementation_guardrails.md) | How to audit, implement, verify, and hand off a change |
