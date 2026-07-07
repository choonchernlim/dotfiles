# AGENTS.md

This file provides guidance to AI agents (Claude Code, Codex, Antigravity, etc) when working with code in this repository.

## What This Repo Does

Personal Mac config managed with nix-darwin and home-manager, currently in a slow migration from an Ansible-based setup ([mac-dev-bootstrap](../mac-dev-bootstrap/)). Both scripts must remain runnable without breaking each other.

## Commands

```bash
# Apply changes after editing any .nix file or rebuild.sh-relevant config
./rebuild.sh

# Validate the config builds without touching the system
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run

# First-time setup on a fresh machine
./bootstrap.sh
```

`home/` files (Neovim, WezTerm, herdr, AI configs) are live-symlinked - editing them takes effect immediately without running `rebuild.sh`. Only run rebuild when changing package lists, system defaults, or shell config in `.nix` files.

## Architecture

```
flake.nix          - entry point; declares the single `user` variable that threads into all other files
configuration.nix  - system-level: macOS defaults, Homebrew declarations (nix-homebrew)
home.nix           - user-level: Nix packages, zsh config, symlinks via mkOutOfStoreSymlink
ai.nix             - home-manager module: all AI agent config (symlinks, env vars, MCP activation)
home/              - actual config files symlinked into ~/.config/, ~/.claude/, etc.
  ai/              - agent-agnostic AI config: shared AGENTS.md, skills/, per-agent settings/ and mcp/
rebuild.sh         - re-applies the flake on every change (wrapper around darwin-rebuild switch)
bootstrap.sh       - one-time setup: installs Determinate Nix, symlinks repo, runs first switch
```

The `user` variable in `flake.nix` is the single source of truth for the username - it flows into `configuration.nix` and `home.nix` via `specialArgs` / `extraSpecialArgs`.

`home.nix` uses `mkOutOfStoreSymlink` to point config paths directly at this repo (via `~/.dotfiles`), so edits to files under `home/` are immediately live - no rebuild needed.

`home/ai/AGENTS.md` is the shared agent policy file - it is symlinked to every agent's canonical location (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.copilot/copilot-instructions.md`, `~/.gemini/antigravity-cli/ANTIGRAVITY.md`). `home/ai/skills/` is similarly symlinked into every agent. Per-agent settings and MCP configs live under `home/ai/settings/` and `home/ai/mcp/`.

## Ansible Coexistence Rules

This repo is **incrementally replacing** mac-dev-bootstrap (Ansible). At any point in time both `./rebuild.sh` and `./mac-dev-bootstrap.sh --tags work` must run without breaking the machine.

**Before adding any new configuration to this repo, check mac-dev-bootstrap first** (`../mac-dev-bootstrap/`). Know what Ansible already manages so Nix does not duplicate, conflict with, or uninstall it.

Current coexistence accommodations - do not revert without understanding the impact:

- `homebrew.onActivation.cleanup = "none"` - keeps Ansible-installed brews and casks intact. Do not change to `"zap"` until fully migrated off Ansible. (The long-term goal post-migration is `"zap"`; see AGENTS.md for rationale.)
- `nix-homebrew.mutableTaps = true` - allows Ansible-managed taps (oven-sh/bun, redis-stack, terraform-linters) to survive.
- `system.defaults` block is commented out - macOS UI settings currently owned by Ansible.
- `programs.zsh.autosuggestion` and `syntaxHighlighting` are disabled - oh-my-zsh (installed by Ansible via `~/.zshrc_conf/`) already provides these.
- `programs.starship` is commented out - Ansible manages p10k as the active prompt.
- `shellAliases` in `home.nix` are commented out - revisit once migrated off Ansible.
- `zsh.initContent` sources `~/.zshrc_conf/*.sh` to load all Ansible-managed shell snippets (oh-my-zsh, p10k, nvm, sdkman, gcloud, aliases).
- The `ai` role in Ansible's `main.yml` is disabled (`# - {role: ai, ...}`) because this repo now owns AI configs.

## Key Invariants (Do Not Silently Revert)

- The `homebrew.onActivation.cleanup = "zap"` setting (post-migration end state) is documented and intentional - it enforces reproducibility by removing undeclared packages on every switch. It is currently set to `"none"` for Ansible coexistence only.
- Never commit `.no-mistakes/` validation evidence to this repo - it is gitignored.
- When disabling a config block during migration, leave the original as a comment (not deleted) so it can be revisited later.
