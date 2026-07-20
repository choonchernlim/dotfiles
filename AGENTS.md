# AGENTS.md

This file provides guidance to AI agents (Claude Code, Codex, Antigravity, etc) when working with code in this repository.

## What This Repo Does

Personal Mac config managed with nix-darwin and home-manager. This repo is the single source of truth for the machine - the predecessor Ansible setup ([mac-dev-bootstrap](../mac-dev-bootstrap/)) is fully retired (all roles disabled; the repo is kept only as historical reference and can be archived).

## Commands

```bash
# Apply changes after editing any .nix file or rebuild.sh-relevant config
./rebuild.sh work       # or: rebuild work (alias works from anywhere)
./rebuild.sh personal
./rebuild.sh work-atdj

# Format all .nix files (nixfmt via treefmt-nix; also runs automatically on Claude edits)
nix fmt

# Validate the config builds without touching the system
# --impure is required: user is derived from $SUDO_USER/$USER at eval time
nix flake check --impure --no-build
nix build --impure .#darwinConfigurations.work.system --dry-run

# Check formatting and lint in isolation
nix build --impure .#checks.aarch64-darwin.formatting
nix build --impure .#checks.aarch64-darwin.pre-commit

# Verify rebuild is warning-free except the one documented upstream options.json warning
# Expected output: empty (no new warnings)
nix eval --impure .#darwinConfigurations.work.system.drvPath 2>&1 | grep -i warning | grep -v options.json | grep -v "uncommitted changes"

# Enter devShell - installs/refreshes .git/hooks/pre-commit (hermetic Nix store paths)
nix develop --impure

# First-time setup on a fresh machine
./bootstrap.sh work     # or: ./bootstrap.sh personal / ./bootstrap.sh work-atdj
```

`home/` files (Neovim, WezTerm, herdr, AI configs) are live-symlinked - editing them takes effect immediately without running `rebuild.sh`. Only run rebuild when changing package lists, system defaults, or shell config in `.nix` files.

## Architecture

```
flake.nix              - entry point; derives `user` from $SUDO_USER/$USER (impure); mkHost helper
                         produces darwinConfigurations.work, .personal, and .work-atdj
hosts/
  work.nix             - { system, darwin, home }  darwin imports homebrew bundles (common + work);
                         home imports the feature modules this host gets (zsh, mise, gcloud, ai,
                         colima, docker, gitea, zscaler)
  personal.nix         - same shape; homebrew common + personal; home imports zsh, mise, gcloud,
                         ai, colima, docker (no gitea, no zscaler - personal is not behind Zscaler)
  work-atdj.nix        - same shape; homebrew common + work-atdj (work-atdj.nix is an empty
                         scaffold for host-specific extras - the 2026-07-15 all-hosts audit found
                         nothing here wasn't already covered by common.nix) + quicklook; home
                         imports zsh, gcloud, ai, colima, docker, gitea, zscaler (no mise/ghostty)
modules/
  darwin/default.nix   - system-level: macOS defaults, Homebrew behavior, Rosetta, brew maintenance
  darwin/homebrew/     - homebrew package bundles: common.nix (the audited 3-way intersection -
                         only packages every host declares live here), personal.nix, work.nix,
                         work-atdj.nix (host-specific extras beyond common.nix; work-atdj.nix is
                         empty right now, extended by hand as machine-specific needs come up)
                         (add/remove a bundle = one import line in hosts/*.nix; lists auto-merge;
                          all 3 hosts import common.nix)
  darwin/quicklook.nix - feature module: QuickLook preview plugins (casks + refresh/reconcile)
  home/default.nix     - core home config every host gets: Nix packages, app-config symlinks, fonts,
                         legacyReconcile (retired vim/pip artifacts)
  home/zsh.nix         - feature module: zsh + starship + direnv, zshReconcile cleanup
  home/mise.nix        - feature module: mise (node, terraform versions), miseReconcile cleanup
  home/gcloud.nix      - feature module: gcloud shell wiring + gcloudSetup (config/components)
  home/ghostty.nix     - feature module: ghostty config symlink + terminal cleanup (iTerm2 removal)
  home/ai.nix          - feature module: all AI agent config (symlinks, env vars, MCP, aiReconcile)
  home/colima.nix      - feature module (work, personal, work-atdj - all 3 hosts): autostarts
                         colima (container runtime) at login via a home-manager launchd agent;
                         generic, not gitea-specific or network-specific; no reconcile - home-manager
                         owns the launchd plist lifecycle itself
  home/docker.nix      - feature module (work, personal, work-atdj - all 3 hosts): reconciles
                         ~/.docker/config.json (credsStore=osxkeychain + credHelpers for GCP
                         Artifact Registry) via an idempotent jq-merge activation - not a home.file
                         symlink, since docker login/gcloud write into the same file at runtime
  home/gitea.nix       - feature module (work, work-atdj): local Gitea+Postgres via Docker Compose,
                         manual gitea-up/-down/-status/-logs shell functions, giteaReconcile;
                         runtime (colima/docker/docker-compose) declared in
                         darwin/homebrew/common.nix; colima itself autostarts via home/colima.nix,
                         so gitea-up is normally only needed once (compose services are restart:
                         unless-stopped)
  home/zscaler.nix     - feature module (work, work-atdj): wiring for the corporate Zscaler MITM
                         proxy - NODE_EXTRA_CA_CERTS, git http.sslcainfo, and trusting the cert
                         inside the colima guest VM (hash-guarded, restarts dockerd only on cert
                         rotation - its trust store is separate from the host's). The cert file
                         itself (~/.ca_certs/zscalercert.pem) stays user-owned, not nix-managed
                         (public repo; bootstrap needs OS-level trust before nix runs anyway) -
                         zscalerReconcile removes the superseded ~/.zshrc_conf/zscaler.sh
                         (each feature module carries its own reconcile; hosts pick modules by import -
                          same pattern as homebrew bundles)
home/                  - actual config files symlinked into ~/.config/, ~/.claude/, etc.
  ai/                  - agent-agnostic AI config: shared AGENTS.md, skills/, per-agent settings/ and mcp/
treefmt.nix            - formatter config (nixfmt RFC-style) consumed by treefmt-nix
rebuild.sh             - re-applies the flake on every change; takes a profile arg, discovered
                         dynamically from hosts/*.nix (work|personal|work-atdj)
bootstrap.sh           - one-time setup: installs Determinate Nix, symlinks repo, runs first switch,
                         installs .git/hooks/pre-commit via `nix develop`
docs/architecture.md   - repo layout, symlink mechanics, formatter toolchain, Ansible coexistence
```

`flake.nix` derives the username from the environment at eval time (`$SUDO_USER` first, then `$USER`),
so no login is hardcoded in the repo. Both `rebuild.sh` and `bootstrap.sh` pass `--impure` to
`darwin-rebuild` / `nix` to allow this environment read.

`home.nix` uses `mkOutOfStoreSymlink` to point config paths directly at this repo (via `~/.dotfiles`), so edits to files under `home/` are immediately live - no rebuild needed.

`home/ai/AGENTS.md` is the shared agent policy file - it is symlinked to every agent's canonical location (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.copilot/copilot-instructions.md`, `~/.gemini/antigravity-cli/ANTIGRAVITY.md`). `home/ai/skills/` is similarly symlinked into every agent. Per-agent settings and MCP configs live under `home/ai/settings/` and `home/ai/mcp/`.

## Ansible: Retired

All mac-dev-bootstrap roles are disabled (commented out in its `main.yml`, per the guardrails' comment-don't-delete rule). Every capability was either ported to nix or deliberately dropped in a modern rewrite:

- **Ported**: homebrew bundles, AI configs (`ai.nix`), shell (`zsh.nix`: nixpkgs autosuggestion/syntaxHighlighting, starship, direnv), tool versions (`mise.nix`: node + terraform), gcloud wiring/config (`gcloud.nix`), ghostty config (`ghostty.nix`), QuickLook plugins pruned to the 4 maintained ones (`darwin/quicklook.nix`), Rosetta install (darwin `extraActivation`), brew cleanup/autoremove (`brewMaintenance` activation), Xcode CLT check (`bootstrap.sh` step 0).
- **Dropped, swept by reconciles**: oh-my-zsh/p10k/spaceship, nvm/sdkman/tfenv (mise replaces), java/maven, iTerm2 (WezTerm + ghostty are the terminals), amix/vimrc (Neovim is the editor), legacy pip packages (requests, crcmod), 4 dead QuickLook plugins.
- `~/.zshrc_conf/` is purely user-owned now (alias-custom.sh, ...); nix only sources it.
  `zscaler.sh` used to live here but is now nix-managed (`home/zscaler.nix`) and swept by its
  own reconcile if it reappears.

Remaining follow-up tasks unlocked by the retirement:
1. ~~**zap flip**~~ - done: audited `brew list` vs declared lists on the work machine,
   declared or dropped each stray (dropped the `redis-stack/redis-stack` tap along with
   its casks; `oven-sh/bun` and `terraform-linters/tap` stay - still used by `bun`/`tflint`),
   and set `homebrew.onActivation.cleanup = "zap"`. The personal-profile audit is also
   done (2026-07-12, via a `brew bundle cleanup --zap` dry-run before the first bootstrap):
   Redis Stack was kept (tap + casks declared in `homebrew/personal.nix`); ngrok and the
   java remnants (sdkman, maven, openjdk) were confirmed as intentional drops.
2. **system.defaults**: design macOS UI defaults deliberately (the block was never actually Ansible-owned; the old comment was stale).

## Key Invariants (Do Not Silently Revert)

- The `homebrew.onActivation.cleanup = "zap"` setting is documented and intentional - it enforces reproducibility by removing undeclared packages on every switch. The zap-flip audit (see "Ansible: Retired") is complete on the `work`/`personal` profiles; declared lists in `./homebrew/{common,work,personal}.nix` are the single source of truth. `common.nix` itself was audited 2026-07-15 against all 3 hosts (work/personal/work-atdj) to be the true 3-way intersection - only packages every host declares live there; anything not universal is duplicated into the specific host bundle(s) that need it. `work-atdj.nix` now imports `common.nix` like the other two profiles and is otherwise an empty scaffold - the user extends it by hand for whatever is unique to that machine.
- Never commit `.no-mistakes/` validation evidence to this repo - it is gitignored.
- When disabling a config block during migration, leave the original as a comment (not deleted) so it can be revisited later.
- When making changes that affect the user-facing workflow (new commands, bootstrap steps, package list, or gotchas), update `README.md` to reflect them. Keep README.md short - link to `docs/` for details rather than expanding inline.
- `rebuild work` must be warning-free except for the one documented upstream `options.json` warning (see "Known upstream warning" below). Any *new* warning that appears must be investigated and eliminated before committing - never let an unexplained warning slide.
- **This nix repo is the single source of truth for all AI-agent configuration** - plugins, skills, extensions, and MCP servers. The `activation.aiReconcile` script in `modules/home/ai.nix` enforces this by removing any undeclared content on every rebuild. To add a capability, declare it in nix. Installing it via an agent CLI (e.g. `claude plugin install`, `agy plugin import`) will be reverted on the next `rebuild work`.

## AI Agent Plugin Reconcile

Each agent maintains its own plugin/extension store that nix does not own, so removed config silently persists. The `aiReconcile` home-manager activation script sweeps these stores on every rebuild:

| Agent             | Mechanism                                                                                                            | Keep-set                                                      |
|-------------------|----------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| Claude            | Reset `installed_plugins.json` + `known_marketplaces.json`; remove cache dir; `claude mcp remove` for undeclared MCP | playwright MCP only                                           |
| Gemini CLI        | Remove all dirs under `~/.gemini/extensions/`; reset `extension-enablement.json -> {}`                               | (none - gemini extensions are the root import source for agy) |
| Antigravity (agy) | Sweep `~/.gemini/antigravity-cli/plugins/*`; reset `import_manifest.json`                                            | playwright (nix symlink declared in `home.file`)              |
| Copilot           | `rm -rf ~/.copilot/installed-plugins`; clear `installedPlugins` in `config.json`                                     | (none)                                                        |

The gemini extension removal is the critical step: `superpowers` and `context7` are installed there and auto-imported into antigravity on `agy` startup. Removing only the antigravity copy without removing the gemini source lets them re-appear on the next `agy` launch.

Stale `.hm-bak` files and agent-created dated backups (`settings.json.YYYYMMDD`) across all agent dirs are also cleaned up by `aiReconcile`.

`aiReconcile` does NOT sweep `~/.copilot/hooks/` or `~/.config/opencode/plugins/` - those are owned by nix symlinks declared in `home.file`, so they are safe from the sweep.

## rtk (Rust Token Killer)

`rtk` rewrites Bash tool calls to token-optimized proxies (e.g. `git status` -> `rtk git status`), cutting context consumption 60-90% on common dev commands. It is wired in **declaratively** - `rtk init` never runs on this machine.

| Agent    | Hook location                                                                   | Mechanism                                                                     |
|----------|---------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| Claude   | `home/ai/settings/claude.json` `hooks.PreToolUse`                               | `rtk hook claude` reads PreToolUse JSON on stdin, emits rewritten command     |
| Copilot  | `home/ai/hooks/copilot/rtk-rewrite.json` -> `~/.copilot/hooks/rtk-rewrite.json` | `rtk hook copilot` (transparent in VS Code Chat; deny+suggest in Copilot CLI) |
| OpenCode | `home/ai/hooks/opencode/rtk.ts` -> `~/.config/opencode/plugins/rtk.ts`          | TypeScript plugin intercepts `tool.execute.before`, calls `rtk rewrite`       |

**Do not run `rtk init`.** It patches agent config files that nix owns as read-only `mkOutOfStoreSymlink` symlinks. Any files it writes are reverted on the next `rebuild work` and create `.hm-bak` churn. To update the hook schemas, capture the new schema from `rtk init -g --no-patch` and update the vendored files in `home/ai/hooks/`.

The binary is installed via Homebrew (`brews = [ ... "rtk" ]` in `modules/darwin/default.nix`).

## Known Upstream Warning

`rebuild work` emits this warning on every run:
```
warning: Using 'builtins.derivation' to create a derivation named 'options.json'
that references the store path '/nix/store/...-source' without a proper context.
```
**This is harmless** - the build succeeds, nothing is broken. It is an upstream nixpkgs bug in `nixos/lib/make-options-doc` (`builtins.toFile` + `unsafeDiscardStringContext` strips store context), surfaced by home-manager's man-page generation. Tracking: [nixpkgs#485682](https://github.com/NixOS/nixpkgs/issues/485682), [home-manager#7935](https://github.com/nix-community/home-manager/issues/7935).

**Workaround (if you want zero warnings):** add `manual.manpages.enable = false;` to `modules/home/default.nix`. Currently left enabled intentionally - revisit once nixpkgs ships a fix.
