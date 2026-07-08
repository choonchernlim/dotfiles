# Architecture

## Repo layout

```
flake.nix              - entry point; derives user from $SUDO_USER/$USER (impure)
                         mkHost helper produces darwinConfigurations.work and .personal
hosts/
  work.nix             - { system, darwin } - profile delta (empty for now)
  personal.nix         - same shape
modules/
  darwin/default.nix   - system-level: macOS defaults, Homebrew, Touch ID for sudo
  home/default.nix     - user-level: packages, zsh, symlinks (mkOutOfStoreSymlink)
  home/ai.nix          - AI agent config: symlinks, env vars, MCP activation
home/                  - config files live-symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - shared AGENTS.md, skills/, per-agent settings/ and mcp/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; takes profile arg (work|personal)
bootstrap.sh           - one-time setup: Nix, symlink, first switch, git hooks
docs/                  - extended documentation (you are here)
```

## How symlinks work

`mkOutOfStoreSymlink` points config paths directly at this repo via `~/.dotfiles`, so edits to files under `home/` are immediately live - no rebuild needed. Only run `rebuild` when changing a `.nix` file.

`home/ai/AGENTS.md` is symlinked to every AI agent's canonical location on first `rebuild`:

| Target path                                | Agent       |
|--------------------------------------------|-------------|
| `~/.claude/CLAUDE.md`                      | Claude Code |
| `~/.codex/AGENTS.md`                       | Codex       |
| `~/.config/opencode/AGENTS.md`             | opencode    |
| `~/.copilot/copilot-instructions.md`       | Copilot     |
| `~/.gemini/antigravity-cli/ANTIGRAVITY.md` | Antigravity |

`home/ai/skills/` is similarly symlinked into every agent. Per-agent settings and MCP configs live under `home/ai/settings/` and `home/ai/mcp/`.

## Formatter and linters

The repo uses treefmt-nix (nixfmt) for formatting and git-hooks.nix for pre-commit enforcement.

```sh
nix fmt                                               # format all .nix files
nix build --impure .#checks.aarch64-darwin.formatting # formatting gate (CI-style)
nix build --impure .#checks.aarch64-darwin.pre-commit # lint gate (statix + deadnix)
nix develop --impure                                  # install .git/hooks/pre-commit
```

The pre-commit hook (installed by `bootstrap.sh` step 4 and `nix develop`) runs nixfmt, statix, and deadnix before every commit. Hook binaries are baked from Nix store paths - no PATH dependency, hermetic on a bare machine.

The Claude repo hook (`.claude/settings.json`) auto-formats `*.nix` files on every Claude edit via a PostToolUse hook. It gracefully no-ops if nixfmt is not yet on PATH (pre-`rebuild`).

## Ansible coexistence

This repo is incrementally replacing [mac-dev-bootstrap](../../mac-dev-bootstrap/). Both must run without breaking each other.

**Before adding new config here, check `../mac-dev-bootstrap/` first** to avoid duplicating or conflicting with what Ansible already manages.

Current accommodations - do not revert without understanding the impact:

| Setting                                          | Current value | Reason                                                                    |
|--------------------------------------------------|---------------|---------------------------------------------------------------------------|
| `homebrew.onActivation.cleanup`                  | `"none"`      | Keeps Ansible-installed brews/casks; target is `"zap"` post-migration     |
| `nix-homebrew.mutableTaps`                       | `true`        | Allows Ansible-managed taps (oven-sh/bun, redis-stack, terraform-linters) |
| `system.defaults`                                | commented out | macOS UI settings owned by Ansible                                        |
| `programs.zsh.autosuggestion/syntaxHighlighting` | disabled      | oh-my-zsh via `~/.zshrc_conf/` provides these                             |
| `programs.starship`                              | commented out | Ansible manages p10k                                                      |
| `shellAliases`                                   | commented out | Revisit once off Ansible                                                  |
| `ai` role in Ansible `main.yml`                  | disabled      | This repo now owns AI configs                                             |
