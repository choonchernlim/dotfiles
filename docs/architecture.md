# Architecture

## Repo layout

```
flake.nix              - entry point; derives user from $SUDO_USER/$USER (impure); one
                         darwinConfiguration per hosts/*.nix; host-<name> checks evaluate
                         every profile; packages.darwin-rebuild pins bootstrap's first switch
hosts/
  work.nix             - { system, darwin, home } - darwin imports homebrew bundles + quicklook;
                         home imports the feature modules this host gets
  personal.nix         - same shape
  work-atdj.nix        - same shape; common homebrew bundle + an empty work-atdj extras bundle;
                         home modules zsh/gcloud/ai/colima/docker/gitea/zscaler/cachepurge
                         (no mise, no langfuse)
modules/
  darwin/default.nix   - imports system.nix + homebrew/
  darwin/system.nix    - nix daemon handoff, Touch ID for sudo, Rosetta, the /etc/dotfiles-profile
                         marker rebuild.sh checks, zsh completion/prompt handoff to home-manager
  darwin/homebrew/     - default.nix: homebrew behavior (zap cleanup, upgrades, --force, brew
                         maintenance + cask dequarantine activations)
                         common.nix: the audited 3-way intersection - only packages every host
                         declares; work.nix / personal.nix / work-atdj.nix: host extras
                         (hosts pick bundles by import; lists auto-merge)
  darwin/quicklook.nix - feature: QuickLook preview plugins (casks + quarantine strip/refresh)
  home/lib/reconcile.nix - mkReconcile: the single way activation shell is written - wraps
                         scripts in writeShellApplication (shellcheck at build time, strict
                         mode, declared tool deps on PATH, atomic json_edit, dry-run aware)
  home/legacy.nix      - one-time migration sweeps; DELETE once every host has run a rebuild
                         containing it (see file header)
  home/default.nix     - core home config every host gets: packages, app symlinks, fonts;
                         imports legacy.nix
  home/zsh.nix         - feature: zsh + starship + direnv (+ zshSetup: ~/.zshrc_conf dir,
                         brew-completions cache)
  home/mise.nix        - feature (work/personal): mise tool versions (+ miseSetup)
  home/gcloud.nix      - feature: gcloud shell wiring, config, components (+ gcloudSetup)
  home/ai/             - feature (directory): AI agent config, one self-contained unit per agent
      default.nix      - umbrella imports + the shared rationale (playwrightMcp, absolute paths)
      claude/          - default.nix (symlinks, MCP, reconcile) + langfuse.nix (TEMPORARY plugin
                         install and CC_LANGFUSE_TAGS patch)
      codex/           - default.nix (per-skill symlinks, config.toml upsert, MCP, backup sweep)
                         + langfuse.nix (TEMPORARY tracing plugin install)
      antigravity.nix  - symlinks, playwright plugin, settings merge-reconcile, agy update,
                         sweep of both agy's plugin store and ~/.gemini/extensions
      copilot.nix      - symlinks, MCP config, plugin-store reset
      opencode.nix     - symlinks, opencode.json (MCP)
  home/colima.nix      - feature (all 3 hosts): autostarts colima at login via a launchd agent
  home/docker.nix      - feature (all 3 hosts): reconciles ~/.docker/config.json credentials
                         via an idempotent atomic jq merge, not a symlink
  home/gitea.nix       - feature (work, work-atdj): local Gitea+Postgres via Docker Compose,
                         gitea-up/-down/-status/-logs shell functions
  home/langfuse.nix    - feature (work only): local Langfuse stack via Docker Compose,
                         langfuse-up/-down/-status/-logs shell functions
  home/zscaler.nix     - feature (work, work-atdj): Zscaler MITM cert wiring - NODE_EXTRA_CA_CERTS,
                         git http.sslcainfo, colima guest VM trust; the cert file itself stays
                         user-owned, not nix-managed (public repo)
  home/cachepurge/     - feature (all 3 hosts): default.nix wraps cache-purge.sh (plain bash,
                         shellcheck-gated) as the `cache-purge` command + the auto activation
home/                  - config files live-symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - shared AGENTS.md, skills/, per-agent settings/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake; profile defaults to /etc/dotfiles-profile and a
                         mismatch aborts without --force
bootstrap.sh           - one-time setup: Nix, symlink, first switch (pinned darwin-rebuild), git hooks
docs/                  - extended documentation (you are here)
```

Conventions: hosts pick feature modules by import, like homebrew bundles; permanent
reconciles live with their feature module via `mkReconcile`; one-time migration sweeps live
in `legacy.nix`; retired brews/casks are removed by homebrew `cleanup = "zap"`, never by
activation shell; anything marked TEMPORARY is a self-contained file meant to be deleted whole.

## How symlinks work

`mkOutOfStoreSymlink` points config paths directly at this repo via `~/.dotfiles`, so edits to files under `home/` are immediately live - no rebuild needed. Only run `rebuild` when changing a `.nix` file.

`home/ai/AGENTS.md` is symlinked to every AI agent's canonical location:

| Target path                                | Agent       |
|--------------------------------------------|-------------|
| `~/.claude/CLAUDE.md`                      | Claude Code |
| `~/.codex/AGENTS.md`                       | Codex       |
| `~/.config/opencode/AGENTS.md`             | opencode    |
| `~/.copilot/copilot-instructions.md`       | Copilot     |
| `~/.gemini/antigravity-cli/ANTIGRAVITY.md` | Antigravity |

`home/ai/skills/` is symlinked as one directory into every agent except Codex. Codex writes its own bundled system skills into `~/.codex/skills/.system/` at runtime, so it gets a real directory with one symlink per skill instead - which means a *new* skill directory needs `git add` + `rebuild` before Codex sees it. Per-agent settings live under `home/ai/settings/`.

## Formatter and linters

The repo uses treefmt-nix (nixfmt) for formatting and git-hooks.nix for pre-commit enforcement.

```sh
nix fmt                                               # format all .nix files
nix build --impure .#checks.aarch64-darwin.formatting # formatting gate (CI-style)
nix build --impure .#checks.aarch64-darwin.pre-commit # lint gate (statix + deadnix)
nix flake check --impure --no-build                   # + evaluates every host profile
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

Activation scripts get the same treatment: `mkReconcile` wraps each one in
`writeShellApplication`, so shellcheck runs at build time and a script calling a tool that is
missing from the hermetic activation PATH fails the build instead of silently no-oping.

The Claude repo hook (`.claude/settings.json`) auto-formats `*.nix` files on every Claude edit via a PostToolUse hook. It gracefully no-ops if nixfmt is not yet on PATH (pre-`rebuild`).

## History

This repo replaced an Ansible setup ([mac-dev-bootstrap](../../mac-dev-bootstrap/), fully retired and kept only as reference). Every capability was ported to a nix feature module or deliberately dropped; `modules/home/legacy.nix` holds the one-time sweeps of the dropped artifacts and is deleted once every host has rebuilt with it. The only open follow-up from that migration is designing `system.defaults` (macOS UI defaults) deliberately - the block in `modules/darwin/system.nix` is a commented placeholder.
