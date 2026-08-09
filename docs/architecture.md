# Architecture

## Repo layout

```
flake.nix              - entry point; derives user from $SUDO_USER/$USER (impure)
                         mkHost helper produces darwinConfigurations.work, .personal, .work-atdj
hosts/
  work.nix             - { system, darwin, home } - darwin imports homebrew bundles;
                         home imports the feature modules this host gets
  personal.nix         - same shape
  work-atdj.nix        - same shape; common homebrew bundle + work-atdj's own (currently empty)
                         extras; home modules zsh/gcloud/ai/colima/docker/gitea/zscaler
                         (no mise/langfuse)
modules/
  darwin/default.nix   - system-level: macOS defaults, Homebrew behavior, Touch ID for sudo
  darwin/homebrew/     - homebrew package bundles: common.nix (audited 3-way intersection - only
                         packages every host declares live here), personal.nix, work.nix,
                         work-atdj.nix (host-specific extras beyond common.nix; empty right now)
                         (hosts pick which bundles to import; lists auto-merge; all 3 hosts import
                          common.nix)
  darwin/quicklook.nix - feature: QuickLook preview plugins (casks + quarantine strip/refresh)
  home/lib/reconcile.nix - mkReconcile helper: the single way activation shell is written -
                         wraps scripts in writeShellApplication (shellcheck at build time,
                         strict mode, declared tool deps on PATH, atomic json_edit, dry-run
                         aware via home-manager's `run`)
  home/legacy.nix      - one-time Ansible-migration sweeps, consolidated; DELETE once every
                         host has run one rebuild containing it (see file header)
  home/default.nix     - core home config every host gets: packages, app symlinks, fonts;
                         imports legacy.nix
  home/zsh.nix         - feature: zsh + starship + direnv (+ zshSetup: ~/.zshrc_conf dir,
                         brew-completions cache)
  home/mise.nix        - feature: mise tool versions - node, terraform (+ miseSetup:
                         `mise install` provisioning)
  home/gcloud.nix      - feature: gcloud shell wiring, config, components (+ gcloudSetup)
  home/ai.nix          - feature: AI agent config - symlinks, env vars, MCP (+ aiReconcile)
  home/colima.nix      - feature (all 3 hosts): autostarts colima (container runtime) at login
                         via a home-manager launchd agent; generic, not gitea- or network-specific
  home/docker.nix      - feature (all 3 hosts): reconciles ~/.docker/config.json
                         (credsStore=osxkeychain + credHelpers for GCP Artifact Registry) via
                         an idempotent atomic jq-merge activation, not a home.file symlink
  home/gitea.nix       - feature (work, work-atdj): local Gitea+Postgres via Docker Compose,
                         started manually with gitea-up/-down/-status/-logs shell functions;
                         runtime (colima/docker/docker-compose) declared in
                         darwin/homebrew/common.nix
  home/langfuse.nix    - feature (work only): local Langfuse stack via Docker Compose,
                         started manually with langfuse-up/-down/-status/-logs shell functions;
                         existing containers restart after login through Colima + Docker
  home/zscaler.nix     - feature (work, work-atdj): corporate Zscaler MITM wiring -
                         NODE_EXTRA_CA_CERTS, git http.sslcainfo, colima guest VM cert trust;
                         the cert file itself stays user-owned, not nix-managed (public repo)
                         (hosts pick feature modules by import, like homebrew bundles;
                          permanent reconciles live with their feature; one-time migration
                          sweeps live in legacy.nix; retired brews/casks are removed by
                          homebrew cleanup = "zap", never by activation shell)
home/                  - config files live-symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - shared AGENTS.md, skills/, per-agent settings/ and mcp/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; takes profile arg, discovered dynamically from
                         hosts/*.nix (work|personal|work-atdj)
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
direnv allow && direnv exec . true                    # install .git/hooks/pre-commit by hand
```

The pre-commit hook (installed by `bootstrap.sh` step 4, and refreshed automatically by
direnv on every `cd` into the repo via `.envrc` -> `use flake . --impure`) runs nixfmt,
statix, and deadnix before every commit. Hook binaries are baked from Nix store paths - no
PATH dependency, hermetic on a bare machine. Because `nix develop`/`nix print-dev-env` alone
only creates a transient GC root, an unrooted hook closure could be reclaimed by Nix's
periodic garbage collection, leaving the hook pointing at a deleted store path. nix-direnv
(`programs.direnv.nix-direnv.enable` in `modules/home/zsh.nix`) fixes this by creating a
persistent GC root under `.direnv/` the first time `direnv allow` is run in the repo.

The Claude repo hook (`.claude/settings.json`) auto-formats `*.nix` files on every Claude edit via a PostToolUse hook. It gracefully no-ops if nixfmt is not yet on PATH (pre-`rebuild`).

## Ansible: retired

[mac-dev-bootstrap](../../mac-dev-bootstrap/) is fully retired - every role in its `main.yml` is commented out (per the guardrails' comment-don't-delete rule) and the repo can be archived. Each capability was ported to a nix feature module or deliberately dropped in a modern rewrite; every drop is swept by the owning module's reconcile activation so any machine, new or drifted, converges from `rebuild` alone.

Highlights of what was dropped rather than ported: oh-my-zsh/p10k/spaceship (native plugins + starship), nvm/sdkman/tfenv (mise), java/maven, iTerm2 (WezTerm is the terminal), amix/vimrc (Neovim), 4 abandoned QuickLook plugins.

Follow-up tasks unlocked by the retirement:

| Task | Detail |
|------|--------|
| zap flip | Audit `brew list` vs declared lists, declare or drop each stray (incl. taps oven-sh/bun, redis-stack, terraform-linters), then set `homebrew.onActivation.cleanup = "zap"` |
| system.defaults | Design macOS UI defaults deliberately - the block was never actually Ansible-owned; the old coexistence comment was stale |
