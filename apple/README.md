# LightCraft for iPad and iPhone

Native SwiftUI app on the unchanged LightCraft Rust engine (UniFFI bridge in `bridge/`). Fork rules: `../FORK.md`.
Contracts between the bridge, the Swift core and the UI: `docs/CONTRACT.md`. Recipe followed: `docs/COOKBOOK.md`.

## UX direction

Apple's Human Interface Guidelines first (system components, Liquid Glass materials, Dynamic Type, keyboard and
pointer, dark and light). Faithful to the desktop app's mental model: the same panels (Edit, Crop & Rotate, Remove,
Masking, Red Eye, Presets, Versions, Info, Keywords, History), the same tools (Brush, Linear/Radial Gradient, White
Balance Selector, Guided Upright) and the same menu structure (File, Edit, View, Photo, Window, Help).

**Reference app: Adobe Lightroom for iPad / iPhone** (the top-ranked, best-reviewed photo development app on the
App Store; the desktop LightCraft already mirrors the non-Classic Lightroom layout). Behaviour and look only,
clean-room: no Adobe assets, icons or code; icons are SF Symbols.

Conventions taken from it:

1. **Two places: the library grid and the loupe.** A grid of photos with a source list (All Photos, albums, smart
   albums) in a sidebar; tapping a photo opens it full-bleed for editing; Back returns to the grid.
2. **iPad: vertical panel switcher on the trailing edge** (Edit, Crop, Remove, Masking, Red Eye, Presets, Versions,
   Info…). Each opens an inspector column beside the photo with collapsible sections (Light, Color, Effects, Detail,
   Optics, Geometry…).
3. **iPhone: bottom tool strip** that scrolls horizontally; the chosen panel's sliders appear in a compact sheet above
   it while the photo stays visible.
4. **Sliders are the primary control**: label left, value right, double-tap resets to default, a drag is one undo
   step.
5. **Press and hold the photo to see the original** (Before); release returns to the edit.
6. **Pinch to zoom, double-tap toggles fit / 100 %**, one-finger pan when zoomed.
7. **Top bar**: back to grid, undo / redo, share (export), and a "…" overflow menu with the full Photo menu.
8. **Filmstrip** under the loupe on iPad to move between photos; swipe left/right on iPhone.
9. **Rating and flag** in the loupe's bottom bar and in each grid cell's context menu.
10. Masking: create a mask from a tool (Brush, Linear, Radial, Subject, Sky…), the mask list in the panel, the effect
    sliders below it.

Per-idiom degradation (iPad windows are resizable): full layout (sidebar + grid / loupe + inspector) → inspector as a
sheet when the window is narrower than 700 pt → iPhone layout (tool strip + sheets) in compact width. Nothing falls off
screen: tool strips scroll as the last resort.

## Build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH="$HOME/.cargo/bin:$PATH"
apple/scripts/build-xcframework.sh --sim-only --debug
cd apple && xcodegen generate
xcodebuild build-for-testing -scheme LightCraft -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd
```

Gates before every commit: `cd apple/bridge && cargo test && cargo clippy --all-targets -- -D warnings`,
`apple/scripts/check-command-ids.sh`, `apple/scripts/tool-coverage.sh`, `apple/scripts/feature-coverage.sh --check`.

Demo: launch with `-LightCraftDemo` — a new library is seeded with the engine's procedural demo photos.

## App icon

`LightCraft/Resources/Assets.xcassets/AppIcon.appiconset` is upstream `assets/app-icon/lightcraft.svg` rendered
full-bleed, opaque, 1024 px (licence: `docs/APP-ICON-LICENSE.txt`, copied from `assets/app-icon/LICENSE.txt`).
