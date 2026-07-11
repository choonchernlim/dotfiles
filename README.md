# dotfiles

Personal Mac setup managed with nix-darwin and home-manager.

- macOS settings, Homebrew (brews + casks), Touch ID for sudo
- zsh with autosuggestions, syntax highlighting, and a starship prompt (config live-symlinked)
- mise for tool versions (node, terraform) - one fast version manager instead of nvm/sdkman/tfenv
- CLI tools: ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font
- Neovim, WezTerm, herdr configs (live-symlinked - edits take effect immediately, no rebuild)
- AI agents: Claude, Codex, Copilot, OpenCode share one `home/ai/AGENTS.md`
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
| Homebrew packages | Edit `modules/darwin/homebrew/{common,personal,work}.nix`    |

## Gotchas

**Homebrew cleanup is `"none"`, not `"zap"`.**
During the Ansible-to-Nix migration, packages not declared in this repo are preserved on each switch. This also means removing a package from a `modules/darwin/homebrew/*.nix` list does not uninstall it - run `brew uninstall <pkg>` once manually. The long-term target is `"zap"` (removes undeclared packages); do not change this until fully migrated off Ansible.

**AI-agent plugins and extensions are nix-managed.**
Anything installed outside this repo (via `claude plugin install`, `agy plugin import`, `gemini extensions install`, etc.) is removed on the next `rebuild work`. To keep a plugin, declare it in nix. See AGENTS.md "AI Agent Plugin Reconcile" for details.

**rtk (Rust Token Killer) hooks are nix-managed - do not run `rtk init`.**
`rtk` rewrites Bash tool calls to use token-optimized proxies (e.g. `git status` -> `rtk git status`). The binary comes from Homebrew; hooks for Claude, Copilot, and opencode are declared in `home/ai/` as nix-owned symlinks. Running `rtk init` would overwrite those symlinks with real files that get reverted on the next `rebuild work`.

**`home/ai/AGENTS.md` is my personal agent policy.**
It installs for Claude, Codex, Copilot, and OpenCode. If you clone this repo, edit or delete it - you'd silently inherit my agent instructions.

**The shell setup is deliberately minimal.**
oh-my-zsh, p10k, and the old alias pack were dropped (not ported) when the Ansible `ohmyzsh` role migrated here - autosuggestions/highlighting come from nixpkgs, the prompt is starship (`home/.config/starship.toml`, live-editable), and the only aliases are `rebuild` and `personal_claude`. Likewise nvm and sdkman were dropped for mise (`home/.config/mise/config.toml`), taking shell startup from ~4s to well under 1s. The `zshReconcile` activation script sweeps all the stale artifacts on every rebuild.

**`rebuild` prints a harmless `options.json` warning** - an upstream nixpkgs bug in home-manager's man-page generation; the build succeeds. See AGENTS.md "Known upstream warning" for details and the one-line workaround.

**Neovim bootstraps on first launch** - clones plugins from GitHub; needs network once.

## Details

See [docs/architecture.md](docs/architecture.md) for repo layout, how symlinks work, formatter toolchain, and Ansible coexistence rules.
