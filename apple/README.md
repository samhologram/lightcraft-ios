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
5. **iPad: persistent tabbed panel dock beside the photo** (Edit, Crop, Remove, Masking, Red Eye, Presets, Versions,
   Info…). Panels stay as tabs until closed; the add menu and Window menu open them. Groups collapse, reorder and
   scroll their selected tab into view. Panel actions live with the selected panel.
6. **iPhone: bottom tool strip** that scrolls horizontally; the chosen panel's sliders appear in a compact sheet above
   it while the photo stays visible.
7. **Sliders are the primary control**: label left, value right, double-tap resets to default, a drag is one undo
   step.
8. **Press and hold the photo to see the original** (Before); release returns to the edit.
9. **Pinch to zoom, double-tap toggles fit / 100 %**, one-finger pan when zoomed.
10. **Top bar**: back to grid, undo / redo, share (export; Save to Photos adds a copy), and a "…" overflow menu with
    Revert and the full Photo menu.
11a. **Full-screen canvas**: the loupe's Full Screen button (or View > Enter Full Screen Canvas, ⌃⌘F) hides every panel, bar and strip so only the photo remains; one floating glass button (or Esc) returns to the standard layout.
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

### Round 7 UX (in progress)

Status: **round 7, in progress** (contract: `docs/CONTRACT.md` §6).

- **Panels like the desktop**: every panel opens from persistent dock tabs or the add menu and Window menu; on iPad
  tab groups collapse and reorder (arrangement remembered); iPhone shows sheets. Panel actions sit with the selected
  panel. The photo has no parallel floating panel/tool rail.
- **iPad menu bar** merges the iPadOS groups with the desktop menus in desktop order, Window and Help last.
- **Hyper-productive**: frequent actions within 1 tap of the loupe; every desktop shortcut incl. Lightroom's single
  keys (P X U 0-5 R D G E, arrows, `\`); ⌘K palette; two-finger tap undo, three-finger tap redo; scrubbable sliders
  with exact entry; context menus; customizable toolbar; last panel and layout remembered; multiple windows. Clean:
  system components, SF Symbols, semantic colours, one primary action per area.
- **Import media**: Files / iCloud / providers (RAW, DNG, TIFF, JPEG, PNG, HEIC + XMP sidecars) are added into the Photos
  library; drag and drop and paste; entry points: grid toolbar Import, File ▸ Import Photos…, ⌘K, empty state.
- **Native decoders**: PhotoKit / ImageIO for thumbnails, previews and non-RAW formats (HEIC via ImageIO: done); the
  engine decodes RAW originals.

### Top 10 workflows: taps-to-do

Taps counted from the open loupe on iPad (hardware-keyboard keys in brackets). "Target" is the round-7 goal; "Measured"
is filled in by the feature pass.

| # | Workflow | Target taps | Measured |
|---|---|---|---|
| 1 | Cull: rate and flag a photo, go to next | 1 per action (rating/flag in bottom bar; 5, P/X, →) | |
| 2 | Open a photo and auto-tone | 2 (tap photo, Auto) | |
| 3 | Adjust exposure | 2 (Edit panel is the default, drag slider; exact entry +1) | |
| 4 | Crop and straighten | 2 (Crop, drag/angle) + 1 to leave | |
| 5 | Apply a preset | 3 (Presets, preset; Panels menu if hidden) | |
| 6 | Copy settings and paste on the next photo | 3 (Copy via menu or ⌘⇧C, next, Paste) | |
| 7 | Remove a spot | 3 (Remove, tap spot, Done) | |
| 8 | Export / share | 2 (Share, destination) | |
| 9 | Revert | 2 ("…" menu, Revert) | |
| 10 | Compare before / after | 1 (press and hold, or `\`) | |

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
