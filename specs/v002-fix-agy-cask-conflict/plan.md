# Plan

- [x] `modules/darwin/homebrew/common.nix` extraActivation: remove /opt/homebrew/bin/agy only if a regular non-`#!` file → verify: flake check; guard returns remove/keep/keep for Mach-O/script/symlink
- [x] `modules/home/ai/antigravity.nix`: delete agyUpdate and header mention → verify: flake check
- [x] `modules/darwin/homebrew/common.nix`: plain `antigravity-cli`, fix comment → verify: flake check
- [x] `scripts/rebuild/format.sh`, `rebuild.sh` comment, fixtures: drop agy row, 28 → 27 steps → verify: rebuild-format check
- [x] Docs: architecture.md, gotchas.md entry → verify: no stale `agy update`/`agyUpdate`
- [x] Full checks and review passes

## Files touched
modules/darwin/homebrew/common.nix (guard), modules/home/ai/antigravity.nix, modules/darwin/homebrew/common.nix, scripts/rebuild/format.sh, scripts/rebuild/rebuild.sh, scripts/fixtures/rebuild-sample.{log,expected}, docs/architecture.md, docs/gotchas.md
