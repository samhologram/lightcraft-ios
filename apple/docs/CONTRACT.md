# LightCraft for iOS and iPadOS: internal contracts

Single source of truth shared by the Rust bridge, the Swift core and the Swift UI. Change it first, then
the code on both sides. Modelled on the PhotoCraft fork (`/Users/samuelhalle/Code/Pc/apple`), adapted to a
photo *library* app (Lightroom-style) whose library is the device's Photos library, instead of a layered image editor.

## 1. Directory ownership

| Path | Owner | What |
|---|---|---|
| `apple/bridge/` | Rust bridge | `lightcraft-apple` crate (own `[workspace]`, UniFFI 0.32, proc-macros only) |
| `apple/scripts/` | Tooling | build-xcframework, check-command-ids, tool-coverage, feature-coverage |
| `apple/project.yml` | Tooling | XcodeGen spec (`.xcodeproj` generated, gitignored) |
| `apple/LightCraftKit/` | Tooling | local Swift package: generated xcframework + generated Swift bindings |
| `apple/LightCraft/Core/` | Swift core | `LibraryModel`, `PhotosLibrary` (PhotoKit), `AppEnvironment` (catalog + asset map), settings, demo seeding, command catalogs |
| `apple/LightCraft/Canvas/` | Swift core | loupe view (zoom/pan), crop overlay, mask/brush/gradient overlays |
| `apple/LightCraft/App/` | Swift UI | `@main`, scenes, `Commands` (menu bar), launch scene |
| `apple/LightCraft/UI/` | Swift UI | `Shared/`, `Pad/`, `Phone/`, `Panels/`, `Commands/` |
| `apple/LightCraft/Resources/` | Swift UI | `Assets.xcassets` (AppIcon), `Info` |
| `apple/LightCraftTests/`, `apple/LightCraftUITests/` | Tests | swift-testing unit tests, XCUITest UI tests + tours |
| `FORK.md`, `.github/workflows/apple-*.yml` | Tooling | fork notes, CI |

Upstream files (everything else) are never edited.

## 2. The data model: the Photos library

The device's Photos library is the user's library (PhotoKit, read/write access). LightCraft has no document type, no
"New / Open library" and no import step. `LightCraftApp` is a plain `WindowGroup`; every window opens on the Photos grid.

**Engine catalog = internal cache.** `AppEnvironment.shared` (one per process, shared by all windows) opens the engine
catalog at `Application Support/LightCraft/Catalog.lightcraftlibrary` (excluded from backup) with
`LibraryHandle.open(dir:, seedDemo: false)`. It holds the engine photo (develop settings, history, rating, flag) of
every Photos asset that was opened. `assets.json` next to it maps `PHAsset.localIdentifier` → engine photo id (`AssetMap`).
The catalog and the map can be deleted at any time: the Photos library is the source of truth; `-LightCraftResetCache`
wipes `Application Support/LightCraft` at launch (tests). If the catalog cannot be opened the app falls back to an
in-memory catalog and shows the error.

**Originals are referenced in place, never imported by the user.** The first time an asset is opened, its original (the
RAW of a RAW+JPEG pair, otherwise the unedited photo) is written with `PHAssetResourceManager` to
`Application Support/LightCraft/Originals/<sanitized local id>/<original file name>` (network allowed) and registered
with `library.import {paths, mode:"add"}`: the engine references that file where it is and copies nothing more. The
cached original is a private cache, not user-visible.

**Opening** (`LibraryModel.openPhoto(at:)`): commit any pending edits of the previously open photo, resolve or create the
engine photo for the asset, `select` it, remember `openLocalID` / `openIndex` / `baselineJSON` (the develop JSON at open
time), `mode = .loupe`. Photos is the only source list: All Photos, Favorites, RAW (found by scanning the asset
resources: PhotoKit has no RAW smart album), a fixed set of Photos smart albums (Recently Added, Screenshots, Selfies,
Panoramas, Live Photos, Portrait, Long Exposure; empty ones hidden) and the user's albums. The fetch is live
(`PHPhotoLibraryChangeObserver`).

**Write-back keeps edits re-editable and revertable in Photos.** Leaving the loupe (`mode` leaves `.loupe`), or the scene
leaving `.active`, calls `commitEdits()`: if `developJson` differs from `baselineJSON`, the photo is rendered at full
resolution (`export_jpeg`, long edge = the photo's, quality 92) and written with `PHContentEditingInput` /
`PHContentEditingOutput` plus `PHAdjustmentData(formatIdentifier: "ca.hologram.lightcraft", formatVersion: "1", data:
<full DevelopSettings JSON, UTF-8>)`, via `PHAssetChangeRequest.contentEditingOutput`. The rendered file is JPEG, or HEIC
when Photos asks for HEIC. iOS asks the person to confirm each modification; declining (`PHPhotosErrorDomain` 3072) is
silent. Writes are serialized (`writeTask`); `savedCount` / `writeBackCount` expose progress. Other errors → `lastError`
("Saving to Photos failed: …").

**Reopening restores settings.** When an asset is first registered, `requestContentEditingInput` is asked with
`canHandleAdjustmentData` = our format identifier; if the asset carries LightCraft adjustment data its JSON is applied
with `develop.merge` (history label "Restore LightCraft edits"). Edits by other apps are not read; the original is the
starting point. Later opens use the cached engine photo, which keeps its own history.

**Revert.** "Revert to Original" calls `PHAssetChangeRequest.revertAssetContentToOriginal()` (Photos' own revert) and
runs `develop.reset` on the engine photo. Not offered in samples mode.

**Permission states** (`PhotosLibrary.status`, `PhotosGridView`), each with its own UI:

| State | UI |
|---|---|
| not determined | "Requesting access…" progress; the system prompt is requested at launch (`bootstrap`) and again by the grid |
| denied / restricted | "Photos Access Needed" empty state with Open Settings; status re-read when the scene becomes active |
| limited | the grid shows the selected photos plus a banner "LightCraft can only see the photos you selected." with **Select More Photos** (`presentLimitedLibraryPicker`) |
| full | the grid |

**Demo / samples mode.** With `-LightCraftDemo` (`AppSettings.isDemo`), when Photos is denied or empty
`LibraryModel.useSamples()` swaps the window to `LibraryHandle.inMemoryDemo()` (`samplesMode = true`): the engine's
procedural sample photos, editable, no write-back, no Revert, `DemoContent.seed` applies a few edits, then `demoReady`.
Otherwise the demo run uses the real Photos library.

**Undo.** The engine owns the history. Each `LibraryScene` passes the scene's `UndoManager` to its `LibraryModel`; after
every journaled command whose `historyId` changed, an undo action calling `handle.undo()` is registered (redo
symmetric; `LibraryModel+Undo.swift`). There is no autosave and no document `snapshot`: the engine catalog is persisted
with `handle.persist()` after registering an asset; edits reach Photos only through write-back above.

**Save a copy / export.** Exports are written to temp files; "Save to Photos" adds them as new assets
(`saveCopies`, add-only access suffices). The share sheet is the other route out.

**Preset import** (Presets panel ▸ Import Presets…, command `file.importPresets`; a preset file opened from
Files is imported too): the picked items are copied (security scoped) to a temp folder. `.cube`, `.zip` and
folders go to `profile.import`; everything except `.cube` goes to `preset.import`. Accepted extensions: `xmp`,
`lrtemplate`, `zip`, `dng`, `lmp`, `mplumpack`, `cube`, `lcpreset`, `lceffect`, and folders. The summary (imported
presets / profiles / mask effects, settings not carried over, per-file failures with reasons) is shown via `lastNotice`.

### Divergences / TODO

- Revert is a button in the loupe's "…" overflow menu ("Revert to Original", `photos.revert`), not an item of the
  generated menu bar's Photo menu.
- The full flow (open → edit → write-back → reopen → revert, and the denied/limited states) is built but not yet verified
  on a simulator (`HANDOFF.md` To do 1); `DevicePhotosUITests` still looks for the old import button.
- Write-back is triggered on leaving the loupe or the scene going inactive, not per edit; a crash while editing may lose
  the edits since the last write-back.
- Edits made by another app, and adjustment data of other format identifiers, are ignored on open.
- Only images are listed (no video, no Live Photo motion); no People / Places / Recents-by-date smart albums.
- Smart Album, Print and Contact Sheet dialogs are not available on iOS yet (README, Known gaps).

## 3. Rust bridge API (UniFFI, crate `lightcraft_apple`, Swift module `LightCraftKit`)

Swift names are what UniFFI 0.32 generates (snake_case → camelCase, `Vec<u8>` → `Data`, `u64` → `UInt64`,
`u32` → `UInt32`, `f64` → `Double`, `Option<T>` → `T?`). Swift catches errors generically
(`error.localizedDescription`). Every exported fn runs engine code under `catch_unwind`; never panics.

```rust
#[derive(uniffi::Error)] pub enum BridgeError { Failed { message: String } }

#[derive(uniffi::Record)] pub struct CommandInfo {
    pub id: String, pub label: String,
    pub menu: Vec<String>,          // ["Photo","Set Rating"]; empty = not in menus
    pub shortcut: Option<String>,   // egui notation "Cmd+Shift+R"
    pub params: String,             // human/agent-readable params doc
    pub is_query: bool,             // journal == false
}
// UI-only desktop commands (views, panels, tools, dialogs), parsed from
// crates/ui-egui/src/menus.rs UI_COMMANDS via include_str! (no egui dependency).
#[derive(uniffi::Record)] pub struct UiCommandInfo {
    pub id: String, pub label: String, pub shortcut: Option<String>,
    pub menu: Vec<String>,          // "Window>Tools" -> ["Window","Tools"]; empty = not in menus
}
// Desktop menu bar order, parsed from crates/ui-egui/src/menubar.rs MENUS + LAYOUT.
#[derive(uniffi::Record)] pub struct MenuSection { pub title: String, pub items: Vec<String> }
// items: command ids, "---" separators, "@Submenu" placeholders, exactly as in LAYOUT.

#[derive(uniffi::Record)] pub struct ParamField {   // structured view of a params doc; best effort
    pub key: String,      // "" = free-form extra params (label = raw fragment)
    pub kind: String,     // "number","integer","bool","choice","string","ids","json"
    pub min: Option<f64>, pub max: Option<f64>,
    pub default_json: Option<String>,
    pub choices: Vec<String>,
    pub label: String,    // humanized key
    pub is_optional: bool,
    pub doc: String,      // the raw fragment for this key
}
#[derive(uniffi::Record)] pub struct ControlInfo {   // lightcraft_develop::CONTROLS
    pub id: String,       // "light.exposure"
    pub label: String, pub section: String,          // section label: "Light","Color",…
    pub section_id: String,                          // "light","color","effects",… (serde camelCase)
    pub min: f64, pub max: f64, pub default_value: f64, pub step: f64, pub decimals: u32,
    pub track: String,    // "plain","centered","temp","tint","gradient","hue","sat","lum","rainbow"
    pub gradient: Vec<String>,                       // hex colours for "gradient" tracks, else empty
}
#[derive(uniffi::Record)] pub struct LibraryState {
    pub photo_count: u64,       // photos in the catalog
    pub visible_count: u64,     // photos in the current view (source+filter)
    pub active: Option<u64>,    // active photo id
    pub selected: Vec<u64>,
    pub can_undo: bool, pub can_redo: bool,
    pub undo_label: Option<String>, pub redo_label: Option<String>,
    pub revision: u64,          // bumps on every call that may change anything
    pub history_id: u64,        // changes when an undo step is recorded / undone / redone
    pub source: String,         // JSON of the current LibrarySource
    pub active_mask: Option<u32>,
    pub unsaved: Option<String>,// Session::unsaved() message
}
#[derive(uniffi::Record)] pub struct PhotoInfo {
    pub id: u64, pub file_name: String, pub format: String,
    pub width: u32, pub height: u32,          // oriented, before crop
    pub rating: u32, pub flag: String,        // "pick","reject","none"
    pub color_label: String,                  // "" or "red","yellow","green","blue","purple"
    pub edited: bool, pub captured: Option<String>,
    pub camera: String, pub lens: String, pub title: String,
}
#[derive(uniffi::Record)] pub struct AlbumInfo {
    pub id: u64, pub name: String,
    pub kind: String,           // "album","smart","folder"
    pub parent: Option<u64>, pub depth: u32, pub count: u64,
}
#[derive(uniffi::Record)] pub struct RenderedImage {
    pub width: u32, pub height: u32,
    pub rgba: Vec<u8>,          // RGBA8 sRGB, premultiplied (opaque photos: alpha 255), stride = width*4
}

#[derive(uniffi::Object)] pub struct LibraryHandle { /* Mutex<Inner{session, revision}> */ }
#[uniffi::export] impl LibraryHandle {
    #[uniffi::constructor] pub fn open(dir: String, seed_demo: bool) -> Result<Arc<Self>, BridgeError>;
        // Session::new() (+ fs setup) then open_library(dir, seed_demo); creates the folder if missing
    #[uniffi::constructor] pub fn in_memory_demo() -> Arc<Self>;   // Session::with_demo(), no disk
    pub fn persist(&self) -> Result<(), BridgeError>;              // flush journal + prefs
    pub fn close(&self) -> Result<(), BridgeError>;                // persist + release lock
    pub fn execute(&self, id: String, params_json: String) -> Result<String, BridgeError>; // result JSON
    pub fn disabled_reason(&self, id: String) -> Option<String>;   // None = enabled (unknown id → Some)
    pub fn undo(&self) -> Result<String, BridgeError>;              // label of undone step
    pub fn redo(&self) -> Result<String, BridgeError>;
    pub fn begin_interaction(&self, label: String) -> Result<(), BridgeError>; // slider drag = 1 step
    pub fn end_interaction(&self) -> Result<(), BridgeError>;
    pub fn state(&self) -> LibraryState;
    pub fn visible_photos(&self) -> Vec<u64>;
    pub fn photo_info(&self, id: u64) -> Option<PhotoInfo>;
    pub fn albums(&self) -> Vec<AlbumInfo>;
    pub fn develop_values(&self, id: u64) -> Result<String, BridgeError>; // JSON {controlId: value} for every CONTROLS id
    pub fn develop_json(&self, id: u64) -> Result<String, BridgeError>;   // full DevelopSettings JSON
    // Rendering: builds the RenderJob under the lock, runs it OUTSIDE the lock (thread-safe;
    // call from a background task), inserts the loaded source back into the cache.
    pub fn render(&self, id: u64, max_w: u32, max_h: u32, before: bool, draft: bool, apply_crop: bool) -> Result<RenderedImage, BridgeError>;
        // apply_crop=false: the full frame (crop overlay); develop settings still applied
    pub fn thumbnail(&self, id: u64, edge: u32) -> Result<RenderedImage, BridgeError>;
    pub fn export_jpeg(&self, id: u64, long_edge: u32, quality: u32) -> Result<Vec<u8>, BridgeError>;
}
#[uniffi::export] pub fn command_catalog() -> Vec<CommandInfo>;
#[uniffi::export] pub fn ui_command_catalog() -> Vec<UiCommandInfo>;
#[uniffi::export] pub fn desktop_menu_layout() -> Vec<MenuSection>;
#[uniffi::export] pub fn command_params(id: String) -> Vec<ParamField>;
#[uniffi::export] pub fn command_platform_support(id: String) -> Option<String>; // None = supported on iOS; Some(reason) from ios-excluded-commands.txt
#[uniffi::export] pub fn develop_controls() -> Vec<ControlInfo>;
#[uniffi::export] pub fn engine_version() -> String;
```

Bridge files: `ui-commands.txt` (every command id the Swift sources reference literally, one per line,
checked by `scripts/check-command-ids.sh` against `command_catalog` + `ui_command_catalog`),
`ios-excluded-commands.txt` (`id<TAB>reason`, e.g. `app.showInFinder	no Finder on iOS`), embedded with
`include_str!` for `command_platform_support`.

## 4. Swift core surface (`apple/LightCraft/Core`)

```swift
@MainActor @Observable final class LibraryModel {
    var handle: LibraryHandle               // the shared catalog; swapped for the in-memory demo in samples mode
    var state: LibraryState                 // refreshed after every call
    var visible: [UInt64]
    var albums: [AlbumInfo]
    var activePhoto: PhotoInfo?
    var developValues: [String: Double]     // active photo, keyed by control id
    var activePanel: Panel                  // .edit .crop .remove .masking .redeye .presets .versions .info .keywords .activity .profiles
    var activeTool: Tool?                   // .brush .linear .radial .wbPicker .guidedUpright (tool.* ids)
    var mode: Mode                          // .grid / .loupe
    var lastError: String?                  // shown as an alert (full message)
    var isDemoReady: Bool                   // `demoReady` marker: Photos grid ready (or samples seeded)
    var samplesMode: Bool                   // engine's in-memory demo photos, no Photos write-back
    var openLocalID: String?                // PHAsset.localIdentifier of the photo open in the loupe
    var photos: PhotosLibrary { get }       // AppEnvironment.shared.photos
    var lastNotice: String?                 // info alert (preset import summary)
    weak var undoManager: UndoManager?

    func run(_ id: String, _ params: [String: Any] = [:]) // execute + refresh + register undo; errors → lastError
    func isEnabled(_ id: String) -> Bool
    func runUI(_ id: String)                // desktop UI-only command ids (view.*, panel.*, tool.*, dialog.*)
    func select(_ id: UInt64)               // library.select {ids:[id], active:id}
    func open(_ id: UInt64)                 // select + mode = .loupe (engine ids; samples mode)
    func openPhoto(at index: Int) async     // Photos grid index: register the asset, select, mode = .loupe
    func bootstrap() async                  // request Photos access, samples fallback in demo mode
    func commitEdits()                      // write changed settings back to Photos (leaving the loupe)
    func revertToOriginal()                 // PhotoKit revert + develop.reset
    func setDevelop(_ control: String, _ value: Double)  // develop.set {values:{control:value}} during a drag
    func beginDrag(_ label: String); func endDrag()
    func refresh()
    func thumbnail(_ id: UInt64, edge: Int) async -> CGImage?   // cached
    func render(_ id: UInt64, size: CGSize, before: Bool, draft: Bool) async -> CGImage?
    func importPresets(_ urls: [URL]) async -> String // profile.import / preset.import, summary in lastNotice
}
enum Panel: String, CaseIterable { case edit, profiles, crop, remove, masking, redeye, presets, info, keywords, versions, activity } // rawValue = suffix of panel.<id>
enum Tool: String, CaseIterable { case brush, linear, radial, wbPicker, guidedUpright }             // rawValue = suffix of tool.<id>
```

More `LibraryModel` members shared between Core and UI:
```swift
    var pendingCommand: String?             // set by menus/palette for a command that takes params; UI shows CommandSheet
    var showCommandPalette: Bool
    var showOriginal: Bool                  // press-and-hold Before
    var showImporter: Bool                  // preset / profile file importer (file.importPresets)
    var showExport: Bool
    var inspectorVisible: Bool              // iPad inspector column
    var zoomToFit: Bool                     // loupe fit vs 100 %
    var thumbSize: Double                   // grid cell edge, pt
    var undoRedoTick: Int                   // bumps on undo/redo so views re-render
    func present(_ id: String)              // runs directly when the command has no required params, else pendingCommand = id
```
Entry views: each `WindowGroup` window builds `LibraryRootView(model:)` with its own `LibraryModel(handle: AppEnvironment.shared.catalog)` (owned by UI, `UI/Shared/LibraryRootView.swift`),
which picks `PadLibraryView` or `PhoneLibraryView` by horizontal size class / window width. Sheets for
`pendingCommand` (`CommandSheet`), the palette (`CommandPaletteView`) and errors (alert with the full message) are
attached in `LibraryRootView`. The menu bar (`App/LibraryCommands.swift`, Core-owned) reads the focused model through
`@FocusedValue(\.libraryModel)`; `LibraryRootView` publishes it with `.focusedSceneValue(\.libraryModel, model)`
(the key is declared in `Core/FocusedValues.swift`).

`CommandCatalog` (Core) wraps `command_catalog()` + `ui_command_catalog()` + `desktop_menu_layout()`:
`menus: [MenuSection]`, `command(id)`, `label(id)`, `shortcut(id)` → `KeyboardShortcut?`.

## 5. Accessibility identifiers (UI tests drive only these)

`tool.<id>`, `panel.<id>`, `command.<id>` (every surface showing a command: menus, context menus,
popovers, sheets), `control.<controlId>` (develop sliders), `section.<sectionId>`, `photo.<id>`
(grid cells), `album.<id>`, `mode.grid`, `mode.loupe`, `loupe`, `demoReady` (hidden marker element,
present once demo seeding finished), `import`, `filmstrip`.

Guided Upright: the tool-strip button is `tool.guidedUpright`; the Crop panel's shortcut button that opens it is
`control.guidedUpright.open` (identifiers are unique). Once active, the overlay surface is
`tool.guidedUpright.overlay` and each guide is `control.guidedUpright.guide.<n>` (n = 0-based index; actions
"Delete Guide" and "Move Start/End Left/Right/Up/Down").
