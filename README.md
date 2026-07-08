# dotfiles

Personal Mac setup managed with nix-darwin and home-manager.

- macOS settings, Homebrew (brews + casks), Touch ID for sudo
- zsh with `rebuild` alias to apply changes from anywhere
- CLI tools: ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font
- Neovim, WezTerm, herdr configs (live-symlinked - edits take effect immediately, no rebuild)
- AI agents: Claude, Codex, Copilot, opencode share one `home/ai/AGENTS.md`
- Nix formatter toolchain with pre-commit hooks (nixfmt, statix, deadnix)

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

## Make it yours

|                   | What to do                                                   |
|-------------------|--------------------------------------------------------------|
| Username          | Nothing - derived from `$USER` at build time                 |
| Profile           | Pass `work` or `personal` to `bootstrap.sh` and `rebuild.sh` |
| CPU arch          | Set `system` in `hosts/work.nix` or `hosts/personal.nix`     |
| Git identity      | Not managed here - git will prompt you on first commit       |
| Homebrew packages | Edit `brews` and `casks` in `modules/darwin/default.nix`     |

## Gotchas

**Homebrew cleanup is `"none"`, not `"zap"`.**
During the Ansible-to-Nix migration, packages not declared in this repo are preserved on each switch. The long-term target is `"zap"` (removes undeclared packages); do not change this until fully migrated off Ansible.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, and opencode. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**High-agency shell aliases are commented out.**
`cc` (claude --dangerously-skip-permissions) and `co` (codex --full-auto) are disabled until the Ansible migration is complete. Read them before uncommenting.

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.

## Details

See [docs/architecture.md](docs/architecture.md) for repo layout, how symlinks work, formatter toolchain, and Ansible coexistence rules.
