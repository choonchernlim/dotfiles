# dotfiles

Personal Mac setup managed with nix-darwin and home-manager.

- 🍎 macOS settings, Homebrew (brews + casks), Touch ID for sudo, QuickLook preview plugins
- 🐚 zsh with autosuggestions, syntax highlighting, and a starship prompt (config live-symlinked)
- 📦 mise for tool versions (Temurin Java 25, node, terraform) - one fast manager instead of sdkman/nvm/tfenv
- ☁️ gcloud shell wiring, config, and components kept in sync
- 🛠️ CLI tools: ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font
- 🔗 Neovim, WezTerm, herdr configs (live-symlinked - edits take effect immediately, no rebuild)
- 🤖 AI agents: Claude, Codex, Copilot, OpenCode, Antigravity share one `home/ai/AGENTS.md` and one `home/ai/skills/`; plugins and MCP servers are nix-declared and reconciled on every rebuild
- 📊 Local Langfuse observability stack (work) via Docker Compose, with Claude and Codex tracing plugins kept in sync by `modules/home/ai/*/langfuse.nix`
- ✨ Nix formatter toolchain with pre-commit hooks (nixfmt, statix, deadnix)
- 🐳 colima autostarts at login via a launchd agent (all 3 profiles) - no manual start needed for any container workload
- 🍵 Local Gitea git server (work, work-atdj) via Docker Compose, localhost-only - `gitea-up` once, then the containers come back on their own; browse to http://localhost:3100
- 🔭 Local Langfuse server (work) via Docker Compose - `langfuse-up` once on a fresh host; browse to http://localhost:3200
- 🔐 `~/.docker/config.json` reconciled to Keychain-backed credentials (all 3 profiles), with GCP Artifact Registry routed through the gcloud helper
- 🔒 Corporate Zscaler MITM cert trusted automatically - host-side (git, npm) and inside the colima guest VM for `docker pull` (work, work-atdj)
- 🧹 `cache-purge` (all 3 profiles): reclaims stale tool caches and dev-tree build artifacts, auto-triggered by `rebuild` when free space drops below 100G; bare `cache-purge` is a dry-run report, `cache-purge --apply` reclaims now, `CACHE_PURGE=off rebuild` skips it

## Profiles

Every profile shares a common base: macOS defaults, Homebrew, zsh, gcloud, AI agents, colima, docker, QuickLook, cache-purge. Each adds a bit more on top:

| Profile     | Adds beyond the common base               |
|-------------|-------------------------------------------|
| `work`      | mise, gitea, Langfuse, Zscaler cert trust |
| `personal`  | mise                                      |
| `work-atdj` | gitea, Zscaler cert trust (no mise)       |

See [docs/architecture.md](docs/architecture.md) for the full per-host module breakdown.

## Prerequisites

- Apple Silicon Mac (Intel: set `system = "x86_64-darwin"` in `hosts/<profile>.nix`)
- Nothing else - `bootstrap.sh` installs Nix

## Fresh-machine setup

```sh
git clone https://github.com/choonchernlim/dotfiles.git
cd dotfiles
./bootstrap.sh work       # or: ./bootstrap.sh personal / ./bootstrap.sh work-atdj
```

`bootstrap.sh` does four things in order:
1. Installs Determinate Nix (skips if already installed)
2. Symlinks this repo to `~/.dotfiles` (required before the first build)
3. Runs the first `darwin-rebuild switch` using the nix-darwin revision pinned in `flake.lock`
4. Installs the git pre-commit hooks via direnv (`.envrc` runs `use flake . --impure`)

The switch records the profile in `/etc/dotfiles-profile`. After that, use `rebuild` for every subsequent change. In a new terminal, direnv prompts a one-time `direnv allow` on first `cd` into the repo - this also pins the hook's Nix store closure so garbage collection can't break it later.

On a fresh work host, create the local service containers once:

```sh
gitea-up
langfuse-up
```

### Validate without applying

```sh
nix flake check --impure --no-build   # evaluates every profile, not just this machine's
nix build --impure .#darwinConfigurations.work.system --dry-run
```

## Daily use

```sh
rebuild         # apply changes to this machine's recorded profile (alias for ./rebuild.sh)
rebuild work    # same, and errors out if this machine is recorded as a different profile
nix fmt         # format all .nix files (also fires automatically on Claude edits)
```

Only run `rebuild` when changing a package list, system default, or `.nix` config. Editing files under `home/` takes effect immediately - they're live-symlinked into place. One exception: a *new* directory under `home/ai/skills/` reaches Codex only after `git add` + `rebuild` (see [docs/gotchas.md](docs/gotchas.md)).

`rebuild` refuses a profile that differs from the one in `/etc/dotfiles-profile` unless you pass `--force`, because Homebrew's zap cleanup would uninstall that machine's packages. It then runs `git pull --rebase --autostash` on `main` and clears stale `*.hm-bak` backups before applying.

## Details

See [docs/architecture.md](docs/architecture.md) for repo layout, how symlinks work, and the formatter toolchain. See [docs/gotchas.md](docs/gotchas.md) for known quirks and non-obvious behavior. See [docs/implementation_guardrails.md](docs/implementation_guardrails.md) for the guardrails AI agents follow when making changes here.
