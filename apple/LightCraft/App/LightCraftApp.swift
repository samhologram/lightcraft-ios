import SwiftUI

@main
struct LightCraftApp: App {
    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { LightCraftDocument() }) { file in
            LibraryScene(document: file.document)
        }
        .commands {
            // File / Edit / View / Photo / Window / Help, generated from the desktop menu layout.
            LibraryCommands()
        }

        DocumentGroupLaunchScene("LightCraft") {
            NewDocumentButton("New Library")
                .accessibilityIdentifier("newDocument")
        } background: {
            LaunchBackground()
        } overlayAccessoryView: { geometry in
            LaunchIcon(titleFrame: geometry.titleViewFrame)
        }
    }
}

/// One library window: the root view plus the hook that mirrors the engine history on this scene's UndoManager.
private struct LibraryScene: View {
    let document: LightCraftDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let model = document.model
        LibraryRootView(model: model)
            .onAppear { model.undoManager = undoManager }
            .onChange(of: undoManager) { _, manager in model.undoManager = manager }
    }
}

// MARK: - Launch scene

struct LaunchBackground: View {
    var body: some View {
        // Plain system background: light or dark with the OS appearance.
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The app icon above the launch scene title, aligned with its leading edge.
/// `titleViewFrame` is the whole band above the action buttons (the large title sits in its
/// lower part), so the icon hangs from the top of that band.
struct LaunchIcon: View {
    let titleFrame: CGRect
    private let side: CGFloat = 64

    var body: some View {
        // The geometry is in window coordinates, so lay out over the whole window.
        Color.clear
            .overlay(alignment: .topLeading) {
                Image("LaunchIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .offset(x: titleFrame.minX + 22, y: titleFrame.minY + 14)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
