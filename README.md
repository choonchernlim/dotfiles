# dotfiles

Personal Mac setup managed with nix-darwin and home-manager.

- 🍎 macOS settings, Homebrew (brews + casks), Touch ID for sudo
- 🐚 zsh with autosuggestions, syntax highlighting, and a starship prompt (config live-symlinked)
- 📦 mise for tool versions (node, terraform) - one fast version manager instead of nvm/sdkman/tfenv
- 🛠️ CLI tools: ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font
- 🔗 Neovim, WezTerm, herdr configs (live-symlinked - edits take effect immediately, no rebuild)
- 🤖 AI agents: Claude, Codex, Copilot, OpenCode share one `home/ai/AGENTS.md`
- ✨ Nix formatter toolchain with pre-commit hooks (nixfmt, statix, deadnix)

## Prerequisites

- Apple Silicon Mac (Intel: set `system = "x86_64-darwin"` in `hosts/work.nix`)
- Nothing else - `bootstrap.sh` installs Nix

## Fresh-machine setup

```sh
git clone https://github.com/choonchernlim/dotfiles.git
cd dotfiles
./bootstrap.sh work       # or: ./bootstrap.sh personal
```

`bootstrap.sh` does four things in order:
1. Installs Determinate Nix (skips if already installed)
2. Symlinks this repo to `~/.dotfiles` (required before the first build)
3. Runs the first `darwin-rebuild switch` (fetches `darwin-rebuild` from nix-darwin 26.05)
4. Installs the git pre-commit hooks via `nix develop`

After that, use `rebuild work` for every subsequent change.

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

See [docs/architecture.md](docs/architecture.md) for repo layout, how symlinks work, formatter toolchain, and Ansible coexistence rules. See [docs/gotchas.md](docs/gotchas.md) for known quirks and non-obvious behavior.
