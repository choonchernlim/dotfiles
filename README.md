# dotfiles

Personal Mac setup managed with nix-darwin and home-manager.

- 🍎 macOS settings, Homebrew (brews + casks), Touch ID for sudo, QuickLook preview plugins
- 🐚 zsh with autosuggestions, syntax highlighting, and a starship prompt (config live-symlinked)
- 📦 mise for tool versions (node, terraform) - one fast version manager instead of nvm/sdkman/tfenv
- ☁️ gcloud shell wiring, config, and components kept in sync
- 🛠️ CLI tools: ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font
- 🔗 Neovim, WezTerm, ghostty, herdr configs (live-symlinked - edits take effect immediately, no rebuild)
- 🤖 AI agents: Claude, Codex, Copilot, OpenCode share one `home/ai/AGENTS.md`
- 📊 Local Langfuse observability stack (work) via Docker Compose, with Claude and Codex tracing plugins kept in sync by `aiReconcile`
- ✨ Nix formatter toolchain with pre-commit hooks (nixfmt, statix, deadnix)
- 🐳 colima autostarts at login via a launchd agent (all 3 profiles) - no manual start needed for any container workload
- 🍵 Local Gitea git server (work, work-atdj) via Docker Compose - since colima autostarts and the containers are `restart: unless-stopped`, `gitea-up` is only needed once ever (or again after a `gitea-down`); browse to http://localhost:3100
- 🔭 Local Langfuse server (work) via Docker Compose - run `langfuse-up` once on a fresh host; Docker restores the containers on later logins; browse to http://localhost:3200
- 🔐 `~/.docker/config.json` reconciled to Keychain-backed credentials (all 3 profiles), with GCP Artifact Registry routed through the gcloud helper
- 🔒 Corporate Zscaler MITM cert trusted automatically - host-side (git, npm) and inside the colima guest VM for `docker pull` (work, work-atdj)

## Profiles

Every profile shares a common base: macOS defaults, Homebrew, zsh, gcloud, AI agents, colima, docker, QuickLook. Each adds a bit more on top:

| Profile     | Adds beyond the common base                     |
|-------------|--------------------------------------------------|
| `work`      | mise, ghostty, gitea, Langfuse, Zscaler cert trust |
| `personal`  | mise, ghostty                                    |
| `work-atdj` | gitea, Zscaler cert trust (no mise, no ghostty)  |

See [docs/architecture.md](docs/architecture.md) for the full per-host module breakdown.

## Prerequisites

- Apple Silicon Mac (Intel: set `system = "x86_64-darwin"` in `hosts/work.nix`)
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
3. Runs the first `darwin-rebuild switch` (fetches `darwin-rebuild` from nix-darwin 26.05)
4. Installs the git pre-commit hooks via `nix develop`

After that, use `rebuild work` for every subsequent change.

On a fresh work host, create the local service containers once:

```sh
gitea-up
langfuse-up
```

Colima starts automatically at login, and Docker restores both stacks after
their containers have been created.

### Validate without applying

```sh
nix flake check --impure --no-build
nix build --impure .#darwinConfigurations.work.system --dry-run
```

## Daily use

```sh
rebuild work    # apply changes (alias installed by Nix; or ./rebuild.sh work from repo root)
nix fmt         # format all .nix files (also fires automatically on Claude edits)
```

Only run `rebuild` when changing a package list, system default, or `.nix` config. Editing files under `home/` takes effect immediately - they're live-symlinked into place.

`rebuild` first runs `git pull --rebase --autostash` on `main` (no-op on other branches) so every machine picks up the latest committed changes before applying. See [docs/gotchas.md](docs/gotchas.md).

## Details

See [docs/architecture.md](docs/architecture.md) for repo layout, how symlinks work, formatter toolchain, and Ansible coexistence rules. See [docs/gotchas.md](docs/gotchas.md) for known quirks and non-obvious behavior. See [docs/implementation_guardrails.md](docs/implementation_guardrails.md) for the guardrails AI agents follow when making changes here.
