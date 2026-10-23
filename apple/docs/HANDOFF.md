# Handoff: LightCraft for iPad and iPhone

State on 2026-10-23, for whoever (person or agent, any platform) continues. Read `COOKBOOK.md` (the recipe),
`CONTRACT.md` (interfaces) and `../README.md` (UX direction, build) first.

## Where it stands

| Area | State |
|---|---|
| Rust bridge (`bridge/`) | Done. `cargo test` + `clippy -D warnings` green; builds for `aarch64-apple-ios-sim`. |
| Scripts | `build-xcframework.sh`, `check-command-ids.sh`, `tool-coverage.sh`, `feature-coverage.sh`, `sync-upstream.sh`, `run-ui-tests.sh` — all pass. |
| App, first version | Runs on iOS 27 simulators: grid, loupe, Edit/Crop/Masking/… panels, generated menus, command palette. |
| Layout fixes | Done: loupe fit margin, HDR-/B&W-conditional sliders, header and chip labels never wrap, denser iPad panel switcher, iPhone sheet keeps the photo visible. |
| **Photos library as the library** | **In progress, builds, NOT verified on a simulator.** `App/LightCraftApp.swift` is a `WindowGroup`; `Core/PhotosLibrary.swift`, `Core/LibraryModel+Photos.swift`, `UI/Shared/PhotosGridView.swift`. `LightCraftDocument.swift` removed. |
| **Lightroom preset import** | **In progress, builds, NOT verified.** `Core/LibraryModel+PresetImport.swift` (desktop's `file.importPresets` flow: `profile.import` for .cube/.zip/folders, `preset.import` for the rest). |
| Coverage tours | Written (`LightCraftUITests/*Tour*.swift`). Panels and tools ran on the old document build; results in `docs/tour-summaries/`. The command tour never completed. |

## To do, in order

1. **Verify the Photos-library model end to end, iPad first, then iPhone** (`scripts/run-ui-tests.sh --only LightCraftUITests/DevicePhotosUITests`):
   open a photo from Photos → edit → leave the loupe → the asset in Photos has LightCraft adjustment data
   (`ca.hologram.lightcraft`) → reopen restores the sliders → Photo ▸ Revert works. Also the denied and limited
   permission states (`xcrun simctl privacy <udid> revoke photos ca.hologram.lightcraft`). The last run of that test
   failed at line 38 ("import label"): the test still looks for an import button from the earlier import-based
   design — update it to the in-place editing flow.
2. **Rewrite `CONTRACT.md` §2 and the README UX section** for the Photos-library model (they still describe the
   `.lightcraftlibrary` document): the device's Photos library is the library; the engine catalog is an internal cache
   in Application Support keyed by `PHAsset.localIdentifier`; originals referenced in place (`library.import` mode
   `add`); edits written back with `PHContentEditingOutput` + adjustment data; `-LightCraftDemo` falls back to the
   engine's sample photos when Photos is empty or denied.
3. **Verify preset import**: a minimal Lightroom XMP preset placed in the app container's Documents, imported via
   Presets ▸ Import Presets…, applied to a photo, exposure changes; the summary shows counts and full failures.
4. **Investigate the crash after ~15 min of app uptime** seen during command tours (iPad and iPhone; no crash log was
   captured). Suspects: memory growth in render/thumbnail caches (`LibraryModel+Rendering.swift`, engine
   `MediaCache` budget — set one with `Session::media.set_budget` in the bridge) or leaked render tasks. Reproduce with
   Instruments (Leaks/Allocations) on the simulator, or watch `xcrun simctl spawn <udid> log stream --predicate
   'process == "LightCraft"'` and `~/Library/Logs/DiagnosticReports`.
5. **Run all suites, iPad then iPhone**: `apple/scripts/run-ui-tests.sh`. Read every `-notes` and `-tour-summary`
   attachment; every "not reached" item is a bug. Known ones:
   - `panel.remove`: `spot.findBlemishes` needs a face-models folder: set `session.face_models_dir` in the bridge to
     Application Support/LightCraft/FaceModels, or exclude face/denoise model commands in `ios-excluded-commands.txt`.
   - `tool.guidedUpright`: no guide overlay of its own (drags land on the crop overlay); add one.
   - Not yet on iOS: `dialog.smartAlbum`, `dialog.newSmartAlbum`, `dialog.print`, `dialog.contactSheet`.
   - iPhone accessibility labels of panel titles read the SF Symbol name; iPad shows "Crop And Rotate".
6. **Haiku feature pass** on the built-in simulator (COOKBOOK §7, last bullet): one agent per area (library/grid,
   loupe and gestures, each Edit section, crop, masking tools, remove/red eye, presets incl. import, versions/history,
   menus and shortcuts with a hardware keyboard, export/share/save to Photos, permissions), iPad then iPhone; Sonnet
   fixes; rerun the affected suites.
7. Device build (COOKBOOK §8) when wanted.

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
