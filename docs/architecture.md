# Architecture

## Repo layout

```
flake.nix              - entry point; derives user from $SUDO_USER/$USER (impure)
                         mkHost helper produces darwinConfigurations.work and .personal
hosts/
  work.nix             - { system, darwin, home } - darwin imports homebrew bundles;
                         home imports the feature modules this host gets
  personal.nix         - same shape
modules/
  darwin/default.nix   - system-level: macOS defaults, Homebrew behavior, Touch ID for sudo
  darwin/homebrew/     - homebrew package bundles: common.nix, personal.nix, work.nix
                         (hosts pick which bundles to import; lists auto-merge)
  darwin/quicklook.nix - feature: QuickLook preview plugins (casks + refresh/reconcile)
  home/default.nix     - core home config every host gets: packages, app symlinks, fonts,
                         legacyReconcile (retired vim/pip artifacts)
  home/zsh.nix         - feature: zsh + starship + direnv (+ zshReconcile)
  home/mise.nix        - feature: mise tool versions - node, terraform (+ miseReconcile)
  home/gcloud.nix      - feature: gcloud shell wiring, config, components (+ gcloudSetup)
  home/ghostty.nix     - feature: ghostty config symlink + terminal cleanup (iTerm2 removal)
  home/ai.nix          - feature: AI agent config - symlinks, env vars, MCP (+ aiReconcile)
                         (hosts pick feature modules by import, like homebrew bundles;
                          each module carries its own reconcile cleanup)
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

## Ansible: retired

[mac-dev-bootstrap](../../mac-dev-bootstrap/) is fully retired - every role in its `main.yml` is commented out (per the guardrails' comment-don't-delete rule) and the repo can be archived. Each capability was ported to a nix feature module or deliberately dropped in a modern rewrite; every drop is swept by the owning module's reconcile activation so any machine, new or drifted, converges from `rebuild` alone.

Highlights of what was dropped rather than ported: oh-my-zsh/p10k/spaceship (native plugins + starship), nvm/sdkman/tfenv (mise), java/maven, iTerm2 (WezTerm + ghostty), amix/vimrc (Neovim), 4 abandoned QuickLook plugins.

Follow-up tasks unlocked by the retirement:

| Task | Detail |
|------|--------|
| zap flip | Audit `brew list` vs declared lists, declare or drop each stray (incl. taps oven-sh/bun, redis-stack, terraform-linters), then set `homebrew.onActivation.cleanup = "zap"` |
| system.defaults | Design macOS UI defaults deliberately - the block was never actually Ansible-owned; the old coexistence comment was stale |
