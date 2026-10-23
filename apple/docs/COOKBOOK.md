# Cookbook: native iPad/iPhone app for a {Function}Craft Rust app

For LLM agents. Replace `<App>`/`<app>` with the target (VectorCraft/vectorcraft, …). Execute in order; each phase ends green before the next.

## 0. Rules
- Fork code only in `apple/` (+ CI workflow, `FORK.md`). Never edit upstream files. Upstream stays mergeable.
- Rust engine untouched; Swift only in `apple/`. No Tauri/webview.
- Every UI action = an engine command by id. Menus, palette and parameter forms are generated from the engine catalog; hand-write only when the generic one is not good enough.
- Don't commit until it builds and runs on a simulator. After that, commit only when asked.
- Subagents: haiku for review/search swarms and simulator driving; sonnet for code. Give each a self-contained brief and its own `-derivedDataPath`.

## 0b. UX direction (decide before writing UI)
- Follow Apple's Human Interface Guidelines for iPad and iPhone as closely as possible: system components, materials (Liquid Glass), navigation, gestures, keyboard and pointer, Pencil, Dynamic Type, accessibility, dark and light. Deviate only where the category demands it, and say why in a code comment.
- Stay faithful to the app's category and to the desktop app's mental model: same tools, same names, same menu structure, adapted to touch.
- Pick a reference app: the most popular, best-reviewed iPad/iPhone app in the same industry. Study its layout, tool organisation, inspector, gestures and per-idiom differences, and match its conventions where they fit Apple's. Behaviour and look only, clean-room: never copy its assets or code. Examples (verify by current App Store rankings):

  | App | Reference |
  |---|---|
  | photo editor | Pixelmator Pro, Affinity Photo |
  | vector | Affinity Designer, Linearity Curve |
  | painting | Procreate |
  | video | LumaFusion, Final Cut Pro for iPad |
  | photo development | Lightroom |
  | PDF | PDF Expert |
  | layout/design | Affinity Publisher, Canva |
- Write down the reference and the 5–10 conventions taken from it in `apple/README.md` before building the UI. Review screenshots against it.

## 1. Bridge (`apple/bridge`, own `[workspace]`)
- UniFFI crate `<app>-apple`, staticlib, path deps on upstream crates. Expose: document object (new/open/export/execute(commandId, paramsJson)/isEnabled/undo/redo/render tiles/thumbnails/stroke/inspect), `commandCatalog()`, `commandParams(id)` (parse the upstream params doc into typed fields), platform support per command.
- Files: `ui-commands.txt` (every id Swift uses), `ios-excluded-commands.txt` (id + reason).
- Gate: `cargo test && cargo clippy --all-targets -- -D warnings`.

## 2. Scripts (`apple/scripts`)
- `build-xcframework.sh [--sim-only] [--debug]`: cargo build per iOS target, uniffi-bindgen Swift, `xcodebuild -create-xcframework`, into a `PhotoCraftKit`-style Swift package.
- `check-command-ids.sh`, `tool-coverage.sh` (every desktop tool mapped in `docs/tool-map.toml`), `feature-coverage.sh --check` (generated `docs/FEATURE_COVERAGE.md`).
- Run all of them plus the bridge gate before every commit.

## 3. App (`apple/<App>`, XcodeGen `project.yml`, iOS 26+, Swift 6)
- `DocumentGroup` + `ReferenceFileDocument`; engine history registered on the scene `UndoManager`. Autosave via `snapshot`.
- Per-idiom UI: iPad floating tool palette + options bar + inspector; iPhone bottom tool strip + sheets. Liquid Glass system styles, no custom chrome.
- Size the layout for the smallest window, not the device: iPadOS windows are resizable, in either orientation, Split View, Stage Manager. Every control stays reachable at every size. Order the degradation: full layout → denser (more columns, icons only, merged groups) → collapse into a menu or sheet → scroll as the last resort. Never let a control silently fall off screen. Check the narrowest and shortest windows in both orientations.
- Every interactive element has a stable accessibility identifier derived from its model id (`tool.<id>`, `toolVariant.<id>`, `command.<id>`), on every surface that shows it: buttons, menus, context menus, popovers, sheets. Agents and UI tests drive the app only through these identifiers.
- iPad menu bar mirrors the desktop menu catalog order: File, Edit, Image, Layer, Type, Select, Filter, 3D, View, Plugins, Window (system, `after: .windowArrangement`), Help (system, `after: .help`). No "Tools" or "All Commands" menu. Single-key tool shortcuts = zero-size hidden buttons on the editor view.
- Launch scene: `DocumentGroupLaunchScene` with `background:` = `Color(uiColor: .systemBackground)` and `overlayAccessoryView:` showing the app icon. The proxy's `titleViewFrame` is the whole band above the buttons, in window coordinates: lay out in a `.ignoresSafeArea()` overlay, offset from `titleViewFrame.minY`.
- App icon: upstream `assets/app-icon/<app>.svg` rendered full-bleed, opaque, 1024 px (remove the rounded clip; iOS masks). Copy the license into `apple/docs/`, note the source in the README.
- Demo launch arg (`-<App>Demo`) seeds a multi-layer composition through engine commands for screenshots and tests. New Document writes `init()`'s blank file and reopens it via `init(configuration:)`: detect "new" there (e.g. only the background layer), not in `init()`.

## 4. Toolchain (macOS)
- Rust lives in `~/.cargo/bin` (often not on PATH). Xcode via `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (no sudo `xcode-select`).
- Simulator runtime: `xcodebuild -downloadPlatform iOS [-buildVersion X]`. Reject runtimes whose `supportedDeviceTypes` has one entry (device-locked, e.g. "iPhone Duo"); delete them. Create devices with `simctl create`.
- Disk: each Rust target dir ≈ 5–11 GB; delete `bridge/target/debug` after cargo gates. Runtime ≈ 8 GB.
- No local Xcode: push and read the macOS CI errors, but check the Actions budget first.

## 5. Compile loop
1. `build-xcframework.sh --sim-only --debug`; `cd apple && xcodegen generate`.
2. `xcodebuild build-for-testing -scheme <App> -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd`.
3. Fix every error; grep the whole tree for the same pattern. Before the first build, have three haiku reviewers sweep thirds of the Swift sources for compile errors, then verify each finding before applying it.
- Known Swift 6 / iOS traps: macOS-only APIs (`openDocument`, `newDocument`, `onPasteCommand`); a `CommandsBuilder`/`ToolbarContentBuilder` takes ≤ 10 items (split into `@CommandsBuilder` properties), and `ForEach` is not a `Commands`; `[CGFloat(1)/3, 2.0/3]` infers `[Any]`; ambiguous `.infinity` in `CGPoint`; main-actor statics read from `nonisolated` code; a `var` captured by `Task`; `NSMutableData` → `as CFMutableData`; a missing `return` in multi-statement bodies; `@MainActor` XCTestCase overriding `setUpWithError`; non-Sendable `CGImage` crossing actors (return `Data`); calls to helpers that don't exist.
- Validate SF Symbol names against the runtime's `CoreGlyphs.bundle/name_availability.plist` (a missing name renders blank).

## 6. Tests
- Unit: bridge smoke tests (swift-testing).
- UI test: launch with the demo arg in dark and light, create a document, wait for a `demoReady` accessibility marker, stroke, add a layer, open panels, attach screenshots. A missing element goes into a `-notes` attachment, not a failure. Read the notes: a green run can be hollow.
- Coverage tours, one per user-facing catalog (tools, menu commands, panels): visit every item through the real UI, act on it, screenshot it, fail only on a crash. Generate the item list from the source of truth, and keep the document valid between items: return to a usable state, e.g. undo or reselect a pixel layer after anything that changes layer type. Run the tours at several window sizes and orientations.
- Treat "not reached" as a bug in the app or the test, never as a pass. Classify each cause, then fix the root: off screen means layout; hidden behind a gesture means a missing identifier; refused by the engine means a wrong test state or a real bug. Record full alert messages, not just titles.
- Run: `xcodebuild test-without-building -destination id=<sim> -resultBundlePath x.xcresult`; export attachments with `xcresulttool export attachments`.
- "Unable to Import Document (DocumentManager error 1)" on New Document = stale simulator state: `simctl erase` the device and rerun.
- Close Simulator.app while tests run; drive and inspect the simulator with screenshots and taps, not by hand.

## 7. Device
- Build the full xcframework (release, no `--sim-only`), set `DEVELOPMENT_TEAM`. With a free team, drop the iCloud entitlement and make the bundle ID unique. On the iPad: Developer Mode on.
