import SwiftUI
@preconcurrency import LightCraftKit

/// Undo through the scene's UndoManager (which mirrors the engine's history); straight to the engine
/// when no manager is attached yet.
@MainActor func uiUndo(_ model: LibraryModel) {
    if let um = model.undoManager {
        um.undo()
    } else {
        _ = try? model.handle.undo()
        model.refresh()
    }
}

@MainActor func uiRedo(_ model: LibraryModel) {
    if let um = model.undoManager {
        um.redo()
    } else {
        _ = try? model.handle.redo()
        model.refresh()
    }
}

/// Undo / redo buttons for toolbars.
struct UndoRedoButtons: View {
    let model: LibraryModel

    var body: some View {
        // `undoRedoTick` is read so the buttons re-render when the history moves.
        let _ = model.undoRedoTick
        Button {
            uiUndo(model)
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.state.canUndo)
        .accessibilityIdentifier("command.edit.undo")
        Button {
            uiRedo(model)
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!model.state.canRedo)
        .accessibilityIdentifier("command.edit.redo")
    }
}

/// Share (export) button: opens the export sheet for the selection.
struct ShareButton: View {
    let model: LibraryModel

    var body: some View {
        Button {
            model.showExport = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(model.state.active == nil && model.state.selected.isEmpty)
        .accessibilityIdentifier("share")
    }
}

/// The "…" overflow menu with the Photo menu (and the other desktop menus below it).
struct OverflowMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            CommandMenuContent(model: model, path: ["Photo"])
            Divider()
            Menu("Edit") { CommandMenuContent(model: model, path: ["Edit"]) }
            Menu("View") { CommandMenuContent(model: model, path: ["View"]) }
            Menu("File") { CommandMenuContent(model: model, path: ["File"]) }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("menu.more")
    }
}

/// Opens the command palette.
struct PaletteButton: View {
    let model: LibraryModel

    var body: some View {
        Button {
            model.showCommandPalette = true
        } label: {
            Label("Command Palette", systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("palette.open")
    }
}

/// Import button (`import`).
struct ImportButton: View {
    let model: LibraryModel

    var body: some View {
        Button {
            model.showImporter = true
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("import")
    }
}
