import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
@preconcurrency import LightCraftKit

/// A photo picked from the Photos library, copied (with its file name) into a temp folder so the
/// engine can import it by path.
private struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("LightCraftImport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedPhoto(url: dest)
        }
    }
}

private struct PendingCommand: Identifiable {
    let id: String
}

/// Entry view of a library document: picks the iPad or iPhone layout, publishes the model to the
/// menu bar, and hosts every sheet, alert and importer.
struct LibraryRootView: View {
    @Bindable var model: LibraryModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager

    @State private var phoneLayout = false
    @State private var commandItem: PendingCommand?
    @State private var paletteShown = false
    @State private var exportShown = false
    @State private var importChooser = false
    @State private var photosPicking = false
    @State private var filesPicking = false
    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        GeometryReader { geo in
            let pad = horizontalSizeClass == .regular && geo.size.width >= 700
            Group {
                if pad {
                    PadLibraryView(model: model)
                } else {
                    PhoneLibraryView(model: model)
                }
            }
            .onChange(of: pad, initial: true) { _, new in phoneLayout = !new }
        }
        .focusedSceneValue(\.libraryModel, model)
        .background { ShortcutButtons(model: model) }
        .overlay(alignment: .topLeading) {
            if model.isDemoReady {
                // Marker for UI tests: present once demo seeding finished.
                Color.clear
                    .frame(width: 2, height: 2)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("Demo ready")
                    .accessibilityIdentifier("demoReady")
            }
        }
        .onAppear {
            if model.undoManager == nil { model.undoManager = undoManager }
        }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        // Sheets: shown after the iPhone panel sheet has closed, so presentations never collide.
        .sheet(item: $commandItem, onDismiss: { model.pendingCommand = nil }) { item in
            CommandSheet(model: model, commandID: item.id)
        }
        .sheet(isPresented: $paletteShown, onDismiss: { model.showCommandPalette = false }) {
            CommandPaletteView(model: model)
        }
        .sheet(isPresented: $exportShown, onDismiss: { model.showExport = false }) {
            ExportSheet(model: model)
        }
        .onChange(of: model.pendingCommand, initial: true) { _, new in
            if let new {
                presentAfterPanel { commandItem = PendingCommand(id: new) }
            } else {
                commandItem = nil
            }
        }
        .onChange(of: model.showCommandPalette, initial: true) { _, on in
            if on { presentAfterPanel { paletteShown = true } } else { paletteShown = false }
        }
        .onChange(of: model.showExport, initial: true) { _, on in
            if on { presentAfterPanel { exportShown = true } } else { exportShown = false }
        }
        .onChange(of: model.showImporter) { _, on in
            if on {
                model.showImporter = false
                importChooser = true
            }
        }
        .confirmationDialog("Import Photos", isPresented: $importChooser, titleVisibility: .visible) {
            Button("Photo Library") { photosPicking = true }
                .accessibilityIdentifier("import.photoLibrary")
            Button("Files") { filesPicking = true }
                .accessibilityIdentifier("import.files")
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $photosPicking, selection: $pickedItems, matching: .images)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            pickedItems = []
            Task { await importPicked(items) }
        }
        .fileImporter(isPresented: $filesPicking, allowedContentTypes: [.image, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await importFiles(urls) }
            } else if case .failure(let error) = result {
                model.lastError = error.localizedDescription
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
                .accessibilityIdentifier("error.ok")
        } message: {
            Text(verbatim: model.lastError ?? "")
        }
    }

    /// On iPhone the panel sheet may be up; close it, wait for the dismissal, then present.
    private func presentAfterPanel(_ action: @escaping @MainActor () -> Void) {
        if phoneLayout && model.inspectorVisible {
            model.inspectorVisible = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                action()
            }
        } else {
            action()
        }
    }

    // MARK: Import

    private func importPicked(_ items: [PhotosPickerItem]) async {
        var urls: [URL] = []
        for item in items {
            do {
                if let picked = try await item.loadTransferable(type: PickedPhoto.self) {
                    urls.append(picked.url)
                }
            } catch {
                model.lastError = error.localizedDescription
            }
        }
        guard !urls.isEmpty else { return }
        await model.importImages(urls)
    }

    /// Files and folders picked in the Files app are read in place while their security scope is open
    /// (the engine copies them into the library's Originals).
    private func importFiles(_ urls: [URL]) async {
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        await model.importImages(urls)
    }
}

/// Zero-size, invisible buttons that give a hardware keyboard the desktop's single-key shortcuts
/// (panels, tools, Grid, Detail). `opacity(0)` rather than `hidden()`: a hidden button does not
/// receive its key equivalent. A focused text field gets bare keys first.
private struct ShortcutButtons: View {
    let model: LibraryModel

    private struct Item: Identifiable {
        let id: String
        let label: String
        let shortcut: ParsedShortcut
    }

    private static let items: [Item] = {
        UICatalog.entries.compactMap { e in
            guard e.isUI, let text = e.shortcut, let parsed = UICatalog.parseShortcut(text) else { return nil }
            let wanted = e.id.hasPrefix("panel.") || e.id.hasPrefix("tool.") || e.id == "view.gridToggle" || e.id == "view.detail"
            guard wanted, e.id != "tool.done", !parsed.modifiers.contains(.command) else { return nil }
            return Item(id: e.id, label: e.label, shortcut: parsed)
        }
    }()

    var body: some View {
        Group {
            ForEach(Self.items) { item in
                Button(item.label) { model.runUI(item.id) }
                    .keyboardShortcut(item.shortcut.key, modifiers: item.shortcut.modifiers)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
