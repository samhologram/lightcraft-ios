import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import LightCraftKit

private struct PendingCommand: Identifiable {
    let id: String
}

/// Entry view of a library document: picks the iPad or iPhone layout, publishes the model to the
/// menu bar, and hosts every sheet, alert and importer.
struct LibraryRootView: View {
    @Bindable var model: LibraryModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var phoneLayout = false
    @State private var commandItem: PendingCommand?
    @State private var paletteShown = false
    @State private var exportShown = false

    var body: some View {
        GeometryReader { geo in
            let pad = horizontalSizeClass == .regular && geo.size.width >= 700
            Group {
                if !model.isCatalogReady {
                    ProgressView("Restoring photo library…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pad {
                    PadLibraryView(model: model)
                } else {
                    PhoneLibraryView(model: model)
                }
            }
            .onChange(of: pad, initial: true) { _, new in phoneLayout = !new }
        }
        .focusedSceneValue(\.libraryModel, model)
        .statusBarHidden(model.canvasOnly)
        .persistentSystemOverlays(model.canvasOnly ? .hidden : .automatic)
        .overlay(alignment: .topTrailing) {
            if model.canvasOnly {
                Button {
                    withAnimation { model.canvasOnly = false }
                } label: {
                    Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .padding(12)
                .accessibilityLabel("Exit Full Screen")
                .accessibilityIdentifier("control.fullscreen.exit")
                .transition(.opacity)
            }
        }
        .background {
            if model.canvasOnly {
                // Esc leaves the canvas-only view (hardware keyboard).
                Button("Exit Full Screen") { withAnimation { model.canvasOnly = false } }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $model.showPresetImporter, allowedContentTypes: LibraryModel.presetContentTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await model.importPresets(urls) }
                } else if case .failure(let error) = result {
                    model.lastError = error.localizedDescription
                }
            }
        }
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
        .overlay(alignment: .top) {
            if model.writeBackCount > 0 {
                Label("Saving to Photos…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("photos.saving")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.commitEdits() }
        }
        .onOpenURL { url in
            // Presets shared into the app (Files > Share > LightCraft).
            if LibraryModel.isPresetFile(url) { Task { await model.importPresets([url]) } }
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
        .alert("LightCraft", isPresented: Binding(
            get: { model.lastNotice != nil },
            set: { if !$0 { model.lastNotice = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastNotice = nil }
                .accessibilityIdentifier("notice.ok")
        } message: {
            Text(verbatim: model.lastNotice ?? "")
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
}

/// Toolbar button that enters the full-screen canvas (loupe only).
struct FullScreenButton: View {
    let model: LibraryModel

    var body: some View {
        Button {
            withAnimation { model.canvasOnly = true }
        } label: {
            Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityIdentifier("control.fullscreen")
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
