# Plan

- [x] Repro (user, needs Touch ID): `sudo -k; sudo -v && sudo sudo -u "$USER" sudo -n true && echo cached || echo re-prompt` → verify: prints `re-prompt`
- [x] `modules/darwin/system.nix`: `security.sudo.extraConfig` with `Defaults:${user} timestamp_type=global` and a why-comment → verify: generated drop-in has terminfo lines plus the new one; `visudo -c -f` parses OK
- [x] `scripts/rebuild/rebuild.sh:154-157` comment: keepalive reaches nested sudo only because the cache is global → verify: `nix flake check --impure --no-build`
- [x] Docs: `docs/gotchas.md` entry, `docs/architecture.md:37`, `README.md:24` → verify: `nix fmt` clean, `scripts/check-warnings.sh` passes
- [x] Pre-commit review (simplify, checks, cohesion/bugs/security passes) → verify: no open confirmed findings. Review fix: keepalive loop now exits with its parent (`kill -0 "$$"`), since an orphan would keep the global cache warm indefinitely
- [ ] User post-rebuild checklist → verify (user): repro prints `cached`; a cask-upgrading rebuild prompts once

## Files touched
modules/darwin/system.nix, scripts/rebuild/rebuild.sh (comment, keepalive exit), modules/darwin/default.nix (import comment), docs/gotchas.md, docs/architecture.md, README.md
