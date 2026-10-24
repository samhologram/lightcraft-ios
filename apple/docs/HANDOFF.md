# Handoff: LightCraft for iPad and iPhone

State on 2026-10-24, for whoever (person or agent, any platform) continues. Read `COOKBOOK.md` (the recipe),
`CONTRACT.md` (interfaces) and `../README.md` (UX direction, build) first.

## Where it stands

| Area | State |
|---|---|
| Rust bridge (`bridge/`), scripts | Done and green (`cargo test`, `clippy -D warnings`, coverage scripts). |
| Photos library as the library, preset import | Built and exercised on the iPad simulator (smoke green at round 6b). |
| Large-library fixes | Done: windowed RAW scan, off-main album counts, debounced reloads. |
| Memory | Done: memory budget and caches (suspect for the old ~15 min crash; watch on device). |
| Cached originals | Startup relink barrier and retryable mapped-photo relink built; synthetic moved-original Swift test passed on iPad (4/4 BridgeSmoke tests), and Crop/Remove commands no longer read the previous app-container path. The prior version marked paths repaired before relink completed. |
| HEIC | Done: decoded through the iOS decoder (ImageIO, 16-bit TIFF to the engine). |
| Full-screen canvas, tour and test fixes | Done: `control.fullscreen`; tour false negatives fixed (`TourSupport.openFirstPhoto` waits for any loupe signal, notes which one). |
| iPad smoke | All green at round 6b. |
| **Round 7** | **In progress** (spec: `CONTRACT.md` §6): PhotoCraft-style persistent iPad dock tabs, pinned Add menu, panel-owned header actions, merged iPad menu bar, productivity (shortcuts, palette, gestures, scrubbable sliders), media import into Photos, native decoders for thumbnails/previews. Dock implementation builds; final simulator validation remains. |
| Coverage tours | Written (`LightCraftUITests/*Tour*.swift`); summaries in `docs/tour-summaries/`. |

## To do, in order

1. **Finish and verify round 7** (see `CONTRACT.md` §6). Bridge cargo test (20/20), clippy, command-ID and tool-coverage gates, generated feature-coverage check, and simulator-target build pass. iPad Stories A/C/D/E/H/I passed on the dock bundle; F then passed on the corrected Masking selector with an actual Subject mask and exposure 0→1. The moved-original Swift regression passed. The latest portrait panel tour reached only Edit, Profiles and Crop (3/11): Remove's native Find menu stayed open around a disabled Find Blemishes row and blocked the following seven dock tabs. Remove now uses an anchored popover that dismisses before dispatching Find Dust; Blemishes remains disabled with its missing-model reason. This new surface builds but is **not yet simulator validated**. The tour reports automatic blemishes as unavailable and manual spot placement as unimplemented, separate from panel navigation. Read the actual `build/results/*-notes` and tour summaries before declaring a pass.
2. **iPhone suites**: `apple/scripts/run-ui-tests.sh`, after the full iPad round-7 suite is green, then iPhone portrait/narrow. Read every
   `-notes` and `-tour-summary`; every "not reached" item is a bug. Known open ones:
   - Remove supports automatic Find Dust. Find Blemishes needs the separately accepted/downloaded YuNet face model;
     the iOS canvas has no manual on-photo spot placement tool yet. Do not count a disabled model action as exercised.
   - `tool.guidedUpright`: overlay of its own (identifiers in CONTRACT §5); verify.
   - Not yet on iOS: `dialog.smartAlbum`, `dialog.newSmartAlbum`, `dialog.print`, `dialog.contactSheet`.
   - iPhone accessibility labels of panel titles read the SF Symbol name.
3. **Haiku feature pass** (COOKBOOK §7, last bullet): one agent per area, iPad then iPhone; fills the "Measured"
   column of the README's top-10 taps table; Sonnet fixes; rerun affected suites.
4. **Device build** (COOKBOOK §8) when wanted; check memory over a long session there.

## Commands

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH="$HOME/.cargo/bin:$PATH"
apple/scripts/build-xcframework.sh --sim-only --debug      # after any bridge change (≈ 8 min cold)
cd apple && xcodegen generate
apple/scripts/run-ui-tests.sh                               # build + all suites, iPad then iPhone
(cd apple/bridge && cargo test && cargo clippy --all-targets -- -D warnings)
apple/scripts/check-command-ids.sh && apple/scripts/tool-coverage.sh && apple/scripts/feature-coverage.sh --check
apple/scripts/sync-upstream.sh                              # import the original LightCraft code
git commit -m "… [skip ci]" && git push origin main         # fork commits never start CI
```

## On another platform

- **Another Mac**: clone `git@github.com:samhologram/lightcraft-ios.git`; install Xcode 26+ with an iOS simulator
  runtime, Rust (`rustup`, then `rustup target add aarch64-apple-ios-sim aarch64-apple-ios`), `brew install xcodegen
  imagemagick`; run the commands above. ≈ 20 GB free disk.
- **Linux / Windows / cloud agents without Xcode**: only the Rust parts run (`apple/bridge`: `cargo test`, `clippy`,
  the coverage scripts). Swift needs macOS: add a fork-only `.github/workflows/apple-ci.yml` on a `macos-26` runner that
  builds the xcframework, runs `xcodebuild build-for-testing` and the simulator suites, and uploads the `.xcresult`
  attachments — and push without `[skip ci]` only for that workflow's runs (mind the Actions budget).
- **Another agent (Claude Code, Codex…)**: point it at this file, `COOKBOOK.md` and `CONTRACT.md`; the rules in
  COOKBOOK §0 (fork-only paths, iPad first, read the notes) apply.
