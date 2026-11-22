# v005 Reclaim more disk space

## Shared understanding
Every host runs low on disk. An audit of the personal host (33 GB free of 461 GB) found these items that `cache-purge` and `brewMaintenance` miss:
- Application Support dirs of superseded JetBrains IDE versions: 2025.3, 2026.1 and 2026.2, about 8 GB.
- Xcode `iOS DeviceSupport`, 14 GB.
- Xcode `DerivedData`, 0.9 GB.
- JetBrains logs, 0.75 GB.
- The Adobe Camera Raw cache, 22 GB.

Decision: extend `cache-purge`, which runs on every rebuild on all 3 hosts, with new rules. Each rule keeps the 14-day staleness gate and appears in the dry run.

Revision 2, after review: the bug and security passes found three rules in the first plan that could destroy data still in use.
- **JetBrains settings.** An older version's settings folder is now deleted only when all three hold:
  - a newer version exists
  - it is stale
  - no installed IDE app claims it as its `dataDirectoryName`
- **DeviceSupport.** These folders are write-once, so mtime cannot tell an in-use one from an unused one. The newest folder per device model is kept, and only older OS builds of that model are age-gated.
- **simctl.** `simctl delete unavailable` is dropped from automation. Simulators count as "unavailable" when the selected Xcode lacks their runtime, so running it would delete live app data. The docs describe the manual command instead.

Not changed, with evidence:
- **Nix generations.** The 47 old system generations hold about 20 MB of store paths the current generation does not use. The whole `/nix/store` is 3.1 GB.
- **Docker build cache.** The `colima-prune` agent in `modules/home/colima.nix` already prunes it weekly. It freed 6.4 GB on one run, and most of what remains was used this week.
- **The JetBrains 2026.2 cache.** This 11 GB is already covered by the `Caches/JetBrains` age gate. The upgrade was on Nov 8, so it goes after Nov 22.
- **Personal data.** Pictures, Downloads, ML models and Claude desktop `vm_bundles` are not touched.

## Assumptions
- Confirmed: deliver this as new `cache-purge` rules, not as a one-off report.
- Confirmed: JetBrains settings are deleted only when superseded, stale and not claimed by any installed app. Installed apps are found through Spotlight (`com.jetbrains.*` bundle ids), with `/Applications`, `~/Applications` and Toolbox 1 globs as a fallback. Their `product-info.json` is parsed in bash, so a missing tool cannot empty the set.
- Review round 2: a settings dir that holds scratch files or database consoles is always kept, because that is user-written content.
- Confirmed: DeviceSupport keeps the folder with the highest OS version per device model. Names look like `iPhone18,2 27.2.1 (24B156)`; legacy names with no model share one group. Birth time is not used, because copies can carry the device's times. Older folders are deleted once they are 14 days old. This covers iOS, watchOS, tvOS and visionOS.
- Confirmed: no automatic simulator cleanup.
- Confirmed: the Camera Raw caches are deleted only whole, once idle for 14 days. The docs recommend capping the cache size in Lightroom.
- Unconfirmed: the Camera Raw caches are also skipped while an Adobe app that reads them is running (Lightroom, Photoshop, Bridge, After Effects, DNG Converter). The `pgrep` match is on the app executable's path, and a `pgrep` error counts as running.
- Review round 2: `is_stale` now treats a `find` error (an unreadable subdir) as not stale. This makes it fail closed for every target, the old ones included.
- Unconfirmed: JetBrains logs and `DerivedData` keep the plain per-child age gate. Both are written on use, so mtime is a valid signal.
- Unconfirmed: the JetBrains version key parses digits as base 10 and the minor version is limited to 1-3 digits. A zero-padded or odd folder name can then never abort the run.

## Definition of done
- On a dry run, `cache-purge` lists every new candidate as STALE, active, or skip with a reason: `newest`, `installed`, or `Adobe app running`.
- A fake-HOME fixture run with `--apply` removes exactly these and keeps the rest:
  - JetBrains: a superseded, stale, uninstalled settings dir goes. Each of these stays: the newest version, a stale superseded dir claimed by a fake installed app, and a superseded dir with a fresh file.
  - DeviceSupport: an older stale build of a model goes, and the newest build of each model stays even when stale.
  - Camera Raw: a stale dir goes, and a dir with a fresh chunk stays.
  - DerivedData: a stale child goes, and a fresh one stays.
- On this host the dry run lists IntelliJIdea2025.3 and 2026.1 as STALE (about 5.3 GB). IntelliJIdea2026.3 is listed as skip, and both DeviceSupport folders are kept as the newest for their model.
- No simctl invocation remains in the script.
- These checks pass:
  - `nix fmt`
  - `statix check .`
  - `deadnix --fail .`
  - `nix flake check --impure --no-build`
  - the `activation` and `rebuild-format` builds
  - `scripts/check-warnings.sh`
- `docs/gotchas.md`, `docs/architecture.md` and `README.md` describe the rules exactly as the code applies them, including the manual simctl command and the Lightroom cap.
