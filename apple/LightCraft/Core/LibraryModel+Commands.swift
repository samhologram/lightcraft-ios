import SwiftUI
@preconcurrency import LightCraftKit

/// Command routing: engine ids run through the bridge, UI-only desktop ids (`view.*`, `panel.*`, `tool.*`,
/// `dialog.*`) are mapped onto this model's state.
extension LibraryModel {
    private static let zoomStep = 1.25
    private static let maxZoom = 16.0

    /// Menus and the palette call this: runs the command directly, or asks for its parameters first.
    func present(_ id: String) {
        let catalog = CommandCatalog.shared
        if catalog.isUI(id) || id == "edit.undo" || id == "edit.redo" {
            run(id)
        } else if catalog.needsSheet(id) {
            pendingCommand = id
        } else {
            run(id)
        }
    }

    func isEnabled(_ id: String) -> Bool {
        if !isCatalogReady && !samplesMode { return false }
        let catalog = CommandCatalog.shared
        switch id {
        case "edit.undo": return state.canUndo
        case "edit.redo": return state.canRedo
        default: break
        }
        if catalog.isUI(id) { return isUIEnabled(id) }
        guard catalog.isKnown(id), catalog.isAvailable(id) else { return false }
        return handle.disabledReason(id: id) == nil
    }

    private func isUIEnabled(_ id: String) -> Bool {
        if Tool.from(commandID: id) != nil { return activePhoto != nil }
        if id.hasPrefix("view.zoom") { return mode == .loupe && activePhoto != nil }
        if id == "view.showOriginal" || id == "view.detail" { return activePhoto != nil }
        return Self.implementsUI(id)
    }

    // MARK: UI-only commands

    /// UI-only desktop ids this model implements (panels and tools are matched by prefix).
    nonisolated static let implementedUIIDs: Set<String> = [
        "view.photoGrid", "view.squareGrid", "view.gridToggle", "view.back", "view.detail",
        "view.zoomIn", "view.zoomOut", "view.zoomFit", "view.zoom100", "view.zoomToggle", "view.showOriginal",
        "view.thumbSizeUp", "view.thumbSizeDown", "view.rightPanel", "panel.close", "tool.none", "tool.done",
        "dialog.export", "file.addPhotos", "dialog.newAlbum", "dialog.newFolder", "dialog.createPreset",
    ]

    nonisolated static func implementsUI(_ id: String) -> Bool {
        implementedUIIDs.contains(id) || Panel.from(commandID: id) != nil || Tool.from(commandID: id) != nil
    }

    /// Runs a desktop UI-only command. Unknown ones set `lastError`; this never crashes.
    func runUI(_ id: String) {
        if let panel = Panel.from(commandID: id) {
            openPanel(panel)
            return
        }
        if let tool = Tool.from(commandID: id) {
            activateTool(tool)
            return
        }
        switch id {
        case "tool.none", "tool.done":
            activeTool = nil
        case "panel.close":
            inspectorVisible = false
            activeTool = nil
        case "view.rightPanel":
            inspectorVisible.toggle()
        case "view.photoGrid", "view.squareGrid", "view.gridToggle", "view.back":
            mode = .grid
            activeTool = nil
        case "view.detail":
            if activePhoto != nil { mode = .loupe }
        case "view.zoomIn":
            zoomToFit = false
            zoomScale = min(Self.maxZoom, zoomScale * Self.zoomStep)
        case "view.zoomOut":
            zoomScale = max(1, zoomScale / Self.zoomStep)
            zoomToFit = zoomScale <= 1.001
        case "view.zoomFit":
            zoomToFit = true
            zoomScale = 1
        case "view.zoom100":
            zoomToFit = false
            zoomScale = max(1, hundredPercentScale)
        case "view.zoomToggle":
            if zoomToFit {
                zoomToFit = false
                zoomScale = max(1, hundredPercentScale)
            } else {
                zoomToFit = true
                zoomScale = 1
            }
        case "view.showOriginal":
            showOriginal.toggle()
        case "view.thumbSizeUp":
            thumbSize = min(AppSettings.thumbSizeRange.upperBound, thumbSize * 1.15)
        case "view.thumbSizeDown":
            thumbSize = max(AppSettings.thumbSizeRange.lowerBound, thumbSize / 1.15)
        case "dialog.export":
            showExport = true
        case "file.addPhotos":
            // Photos are the library: with limited access this lets the person add more of them.
            // Photos are the library: add files from Files/iCloud into it (limited access: pick more first).
            if photos.status == .limited { photos.presentLimitedPicker() } else { presentMediaImport() }
        case "file.importPresets":
            showPresetImporter = true
        case "dialog.newAlbum", "dialog.newFolder":
            pendingCommand = "album.create"
        case "dialog.createPreset":
            pendingCommand = "preset.create"
        default:
            lastError = "Not available on iPad/iPhone yet: \(CommandCatalog.shared.label(id))"
        }
    }

    /// `panel.<x>`: show the panel (and the loupe) with the inspector open.
    func openPanel(_ panel: Panel) {
        if let tool = activeTool, tool.panel != panel { activeTool = nil }
        activePanel = panel
        if activePhoto != nil { mode = .loupe }
        inspectorVisible = true
    }

    /// `tool.<x>`: choose the tool, open its panel, show the loupe.
    func activateTool(_ tool: Tool) {
        activeTool = tool
        if let panel = tool.panel { activePanel = panel }
        if tool == .brush { brushMaskID = nil }
        if activePhoto != nil { mode = .loupe }
        inspectorVisible = true
    }
}
