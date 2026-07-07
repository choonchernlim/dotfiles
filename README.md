# dotfiles

Watch the walkthrough: https://youtu.be/5N-okeDdIuI

My personal Mac setup, managed with nix-darwin and home-manager.
One repo, one command, and a fresh Mac ends up configured the same way every time.

## What you get

Running the switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font)
- Shell (zsh, `rebuild` alias to apply changes from anywhere)
- Touch ID for sudo (no more typing your password for `rebuild`)
- Editor (Neovim config)
- Terminal (WezTerm config)
- Agent configs (Claude, Codex, Copilot, and opencode all share one `home/ai/AGENTS.md`)

## Prerequisites

- Apple Silicon Mac, by default.
- Intel Mac: change one line.
  In `hosts/work.nix` (or `hosts/personal.nix`), set `system = "x86_64-darwin";` (the comment right there tells you the same thing).

## Fresh-machine setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/kunchenguid/dotfiles.git
cd dotfiles
```

Before you run it: review "Make it yours" below.
Check the CPU architecture in `hosts/work.nix` or `hosts/personal.nix` if needed, and read the Homebrew cleanup warning.
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh work       # on a work machine
./bootstrap.sh personal   # on a personal machine
```

`bootstrap.sh` does three things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `modules/home/default.nix` points at config files through `~/.dotfiles`.
3. Runs the first `darwin-rebuild switch`.
   It fetches the `darwin-rebuild` tool from the nix-darwin 26.05 release branch, then applies this repo's locked flake config.
   Your macOS username is derived from the environment automatically - nothing to personalize.

After that, `darwin-rebuild` exists and you're on the normal workflow below.

### Validate without applying

Once Nix is installed (`bootstrap.sh` step 1 handles that), you can check that the config builds without touching your system - handy when you have edited something:

```sh
# --impure is required: the username is derived from $USER at eval time
nix flake check --impure --no-build
nix build --impure .#darwinConfigurations.work.system --dry-run
```

## Daily use

Edit the config files in place, then apply:

```sh
rebuild work        # from anywhere in the terminal (alias installed by modules/home/default.nix)
```

That's it. After the first successful rebuild, sudo prompts (including rebuild itself) use Touch ID instead of your password.
No separate build-and-copy step.

## Make it yours

This repo is mine.
If you clone it, review these before you run `bootstrap.sh`:

- **Username**: nothing to do - your macOS login is derived from the environment automatically at build time.
  No line to edit anywhere.
- **Profile** (`work` or `personal`): pass it to `bootstrap.sh` and `rebuild.sh` as the first argument.
  Two flake targets exist (`darwinConfigurations.work` and `.personal`), both in `flake.nix`.
- **CPU architecture**: set `system` in `hosts/work.nix` or `hosts/personal.nix` (see Prerequisites above).

**Git identity:** this config deliberately does not set your git name or email.
Git will stop your first commit and tell you to set them (`git config --global user.name "Your Name"` and `git config --global user.email you@example.com`).
If you'd rather manage that declaratively, add this back to `modules/home/default.nix` with your own identity:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "you@example.com";
  };
};
```

**Homebrew cleanup warning:** `modules/darwin/default.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `modules/darwin/default.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

**About `herdr`:** it's in the `brews` list.
It's a real public Homebrew formula (`brew info herdr` finds it in homebrew-core, no tap needed), so it will install fine.
If you don't use it, just remove it from `brews` in your copy.

**Heads-up:**

- `home/ai/AGENTS.md` is my personal agent policy, and `ai.nix` installs it for Claude, Codex, Copilot, and opencode.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/ai/AGENTS.md` if you don't want that.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  They're convenient for me, but know what they do before you use them. (Currently commented out - uncomment once migrated off Ansible.)

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, nix-darwin, home-manager, and nix-homebrew.
  Derives the username from `$SUDO_USER`/`$USER` (impure), and produces two flake targets: `work` and `personal`.
- `hosts/work.nix` / `hosts/personal.nix` - per-profile data: CPU architecture, and a place to add profile-specific packages later.
- `modules/darwin/default.nix` - shared system-level config: macOS defaults, Homebrew, Touch ID for sudo.
- `modules/home/default.nix` - shared user-level config: shell, packages, the `rebuild` alias, and the symlinks described below.
- `modules/home/ai.nix` - home-manager module: all AI agent config (shared AGENTS.md, skills, per-agent settings and MCP, Playwright MCP activation).
- `rebuild.sh` - re-applies the config after the first switch.
  Takes a profile arg: `rebuild work` or `rebuild personal` (or just type `rebuild work` from anywhere).
- `home/` - the actual config files that get symlinked into place (Neovim, WezTerm, herdr).
  - `home/ai/` - agent-agnostic AI config: `AGENTS.md`, `skills/`, per-agent `settings/` and `mcp/`.

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`modules/home/default.nix` and `modules/home/ai.nix` use `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` and `~/.claude/CLAUDE.md` straight at files in this repo, so the two never drift out of sync.
You only run `rebuild work` when you change something that isn't just a symlinked file, like a package list, a system default, or a `.nix` config.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.
