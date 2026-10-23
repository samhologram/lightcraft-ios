# LightCraft for iPad and iPhone

Native SwiftUI app on the unchanged LightCraft Rust engine (UniFFI bridge in `bridge/`). Fork rules: `../FORK.md`.
Contracts between the bridge, the Swift core and the UI: `docs/CONTRACT.md`. Recipe followed: `docs/COOKBOOK.md`.

## UX direction

Apple's Human Interface Guidelines first (system components, Liquid Glass materials, Dynamic Type, keyboard and
pointer, dark and light). Faithful to the desktop app's mental model: the same panels (Edit, Crop & Rotate, Remove,
Masking, Red Eye, Presets, Versions, Info, Keywords, History), the same tools (Brush, Linear/Radial Gradient, White
Balance Selector, Guided Upright) and the same menu structure (File, Edit, View, Photo, Window, Help).

**Reference apps: Adobe Lightroom for iPad / iPhone** (the top-ranked, best-reviewed photo development app on the App
Store; the desktop LightCraft already mirrors the non-Classic Lightroom layout) for the editor, and **Photos' own
editor** for library integration. Behaviour and look only, clean-room: no Adobe assets, icons or code; icons are SF
Symbols.

**The library is the Photos library.** There is no LightCraft library file and no import step: the grid shows the
photos, albums and smart albums of the device's Photos library (PhotoKit). Opening a photo edits it in place; the engine
keeps a private cache of opened photos (Application Support) that the user never sees. Details: `docs/CONTRACT.md` §2.

Conventions taken from the references:

1. **Two places: the Photos grid and the loupe.** A grid of the photos of the chosen source (All Photos, Favorites,
   RAW, Photos' smart albums, your albums) with a source list in a sidebar; tapping a photo opens it full-bleed for
   editing; Back returns to the grid.
2. **Edits are written back to Photos when you leave the loupe** (or the app goes to the background), as Photos'
   own editor does: the photo in Photos shows the edit, iOS asks you to confirm the change, and the edit stays
   re-editable (LightCraft stores its settings with the photo, `ca.hologram.lightcraft`) and revertable in Photos.
   Reopening the photo in LightCraft restores the sliders.
3. **Revert**: "Revert to Original" in the loupe's "…" menu returns the photo to its original, like Photos' Revert.
4. **Permissions have their own screens**: asking for access, denied (Open Settings), limited (the grid shows the
   selected photos with a "Select More Photos" banner), full.
5. **iPad: vertical panel switcher on the trailing edge** (Edit, Crop, Remove, Masking, Red Eye, Presets, Versions,
   Info…). Each opens an inspector column beside the photo with collapsible sections (Light, Color, Effects, Detail,
   Optics, Geometry…).
6. **iPhone: bottom tool strip** that scrolls horizontally; the chosen panel's sliders appear in a compact sheet above
   it while the photo stays visible.
7. **Sliders are the primary control**: label left, value right, double-tap resets to default, a drag is one undo
   step.
8. **Press and hold the photo to see the original** (Before); release returns to the edit.
9. **Pinch to zoom, double-tap toggles fit / 100 %**, one-finger pan when zoomed.
10. **Top bar**: back to grid, undo / redo, share (export; Save to Photos adds a copy), and a "…" overflow menu with
    Revert and the full Photo menu.
11. **Filmstrip** under the loupe on iPad to move between photos; swipe left/right on iPhone.
12. **Rating and flag** in the loupe's bottom bar and in each grid cell's context menu.
13. Masking: create a mask from a tool (Brush, Linear, Radial, Subject, Sky…), the mask list in the panel, the effect
    sliders below it.
14. **Presets**: Presets ▸ Import Presets… imports Lightroom XMP presets (`.xmp`, `.lrtemplate`, `.dng`, zips) and
    profiles (`.cube` LUTs, folders) plus LightCraft packs; the summary lists what was imported, what was not carried
    over and every failure.

Per-idiom degradation (iPad windows are resizable): full layout (sidebar + grid / loupe + inspector) → inspector as a
sheet when the window is narrower than 700 pt → iPhone layout (tool strip + sheets) in compact width. Nothing falls off
screen: tool strips scroll as the last resort.

### Known gaps on iOS

- **Smart Album / New Smart Album, Print, Contact Sheet** dialogs are not available yet (no iOS equivalent built;
  `ios-excluded-commands.txt` gives no other reason).
- **Remove's blemish finder** requires downloadable face models, not bundled (looked up in Application Support/LightCraft/FaceModels).
- **Guided Upright** has no guide overlay of its own yet (being added).
- Not yet verified on a simulator: the Photos write-back / revert / permission flows and preset import
  (`docs/HANDOFF.md`).

## Build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH="$HOME/.cargo/bin:$PATH"
apple/scripts/build-xcframework.sh --sim-only --debug
cd apple && xcodegen generate
xcodebuild build-for-testing -scheme LightCraft -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd
```

Gates before every commit: `cd apple/bridge && cargo test && cargo clippy --all-targets -- -D warnings`,
`apple/scripts/check-command-ids.sh`, `apple/scripts/tool-coverage.sh`, `apple/scripts/feature-coverage.sh --check`.

Demo: launch with `-LightCraftDemo` — when Photos is denied or empty, the engine's procedural demo photos are shown instead (editable, no write-back).

## App icon

`LightCraft/Resources/Assets.xcassets/AppIcon.appiconset` is upstream `assets/app-icon/lightcraft.svg` rendered
full-bleed, opaque, 1024 px (licence: `docs/APP-ICON-LICENSE.txt`, copied from `assets/app-icon/LICENSE.txt`).
