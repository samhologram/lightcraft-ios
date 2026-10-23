import SwiftUI

@main
struct LightCraftApp: App {
    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        // The Photos library is the library: every window opens straight onto it. Windows share one
        // engine catalog (the internal cache of opened photos).
        WindowGroup {
            LibraryScene()
        }
        .commands {
            // File / Edit / View / Photo / Window / Help, generated from the desktop menu layout.
            LibraryCommands()
        }
    }
}

/// One library window: the root view plus the hook that mirrors the engine history on this scene's UndoManager.
private struct LibraryScene: View {
    @State private var model = LibraryModel(handle: AppEnvironment.shared.catalog)
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        LibraryRootView(model: model)
            .onAppear { model.undoManager = undoManager }
            .onChange(of: undoManager) { _, manager in model.undoManager = manager }
            .task { await model.bootstrap() }
    }
}
