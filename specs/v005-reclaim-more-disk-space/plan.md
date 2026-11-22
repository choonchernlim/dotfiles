# v005 Plan (revision 2)

- [x] Record the spec and plan pair → verify: both files exist and `refs/grill-me/v5` is reserved
- [x] Add `~/Library/Logs/JetBrains` and Xcode `DerivedData` to `AGE_GATED_PARENTS` → verify: the dry run lists each child as STALE or active
- [x] Whole-dir gate for the Adobe Camera Raw caches → verify: the dry run lists both as active on this host
- [x] First-pass superseded-JetBrains scan, simctl GC and the docs (superseded by revision 2 below)
- [x] Remove simctl entirely (the `gc_command` arm, the run_tool_gc case and skip, the Xcode PATH entry, header and docs claims); the docs give the manual `xcrun simctl delete unavailable` with its caveat → verify: `grep -n simctl modules/home/cachepurge/cache-purge.sh` is empty
- [x] Replace the JetBrains scan with a shared `scan_keep_newest PARENT RANKFN [GUARDFN]`. Per group it keeps the max rank and logs it as `skip (newest ...)`; each older dir goes to the guard (which logs `skip (<reason>)`) or to `consider`. JetBrains: rank is a base-10 version key with the minor limited to `{1,3}` digits, and the guard is "an installed app claims this dataDirectoryName" → verify: the dry run shows IntelliJIdea2025.3 and 2026.1 as STALE, 2026.2 as active, and 2026.3 as `skip (newest ...)`
- [x] Move iOS/watchOS DeviceSupport out of `AGE_GATED_PARENTS` into `scan_keep_newest`, grouped by device model (legacy names share one group) and ranked by the OS version in the name (birth time tied in the fixture: copies can carry old times) → verify: both DeviceSupport dirs on this host show as `skip (newest ...)`
- [x] Camera Raw guard: skip with `skip (Adobe app running)` while `pgrep` finds Lightroom, Photoshop or Bridge → verify: the dry run on this host shows active or skip, never STALE while Lightroom is open
- [x] Fix the cohesion nits:
  - the script summary line and the safety bullet on scopes
  - locals declared at the top of each function
  - reflow the comments and `docs/architecture.md`
  - gotchas: the title, a blank line before the list, and accurate DeviceSupport wording

  → verify: re-read the diff
- [x] Fake-HOME fixture run, dry run then `--apply`, covering every case in the spec's definition of done (the fake installed IDE lives in the fake `$HOME/Applications`, so no test-only override) → verify: exactly the expected dirs are removed
- [x] Run `nix fmt`, `statix check .`, `deadnix --fail .`, `nix flake check --impure --no-build`, the `activation` and `rebuild-format` builds, and `scripts/check-warnings.sh` → verify: all green
- [x] Pre-commit review again: the bug pass and a security pass on the revised diff; show the diff for approval → verify: findings are fixed or listed (round 2 fixes: fail-closed pgrep and is_stale, Spotlight IDE lookup, bash-parsed product-info, scratches/consoles guard, tvOS/visionOS)
- [x] Hand over a post-rebuild checklist (I never run rebuild) → verify: the checklist covers a dry run, the rebuild summary line, and `df -h /`

## Files touched
- `modules/home/cachepurge/cache-purge.sh`: the header, `AGE_GATED_PARENTS`, `CAMERA_RAW_CACHES`/`ADOBE_APPS` and its guard, `is_stale` (fails closed), the new `scan_keep_newest` with its JetBrains and DeviceSupport rank/guard functions, `run_tool_gc`/`gc_command` (simctl removed), and the main sequence
- `modules/home/cachepurge/default.nix`: header comment
- `docs/gotchas.md`, `docs/architecture.md`, `README.md`
