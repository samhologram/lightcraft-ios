import SwiftUI
import Photos

/// The Photos library grid: thumbnails of the current source (PhotoKit). Tapping a photo opens it in the
/// loupe (its original is registered with the engine the first time).
struct PhotosGridView: View {
    let model: LibraryModel

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var photos: PhotosLibrary { model.photos }

    var body: some View {
        Group {
            if photos.isDenied {
                ContentUnavailableView {
                    Label("Photos Access Needed", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("LightCraft edits the photos in your Photos library. Allow access in Settings to see them here.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("photos.openSettings")
                }
            } else if !photos.isAuthorized {
                ProgressView("Requesting access…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await photos.requestAccess() }
            } else {
                content
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { photos.refreshStatus() } }
        .modifier(MediaImportModifier(model: model))
    }

    private var content: some View {
        VStack(spacing: 0) {
            if photos.status == .limited { limitedBanner }
            if photos.count == 0 {
                ContentUnavailableView {
                    Label("No Photos", systemImage: "photo")
                } description: {
                    Text("There are no photos in this album.")
                } actions: {
                    Button { model.presentMediaImport() } label: { Label("Import from Files", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("photos.emptyImport")
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: max(60, model.thumbSize), maximum: max(60, model.thumbSize) * 1.6), spacing: 3)],
                        spacing: 3
                    ) {
                        ForEach(0..<photos.count, id: \.self) { index in
                            PhotosCell(model: model, index: index, edge: max(60, model.thumbSize))
                        }
                    }
                    .padding(3)
                }
            }
        }
        .overlay { openingOverlay }
        .desktopShortcuts(model: model)
        .multiFingerUndoRedo(model: model)
    }

    @ViewBuilder
    private var openingOverlay: some View {
        if model.isOpening {
            ProgressView("Opening…")
                .padding(20)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("photos.opening")
        }
    }

    private var limitedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
            Text("LightCraft can only see the photos you selected.")
                .font(.footnote)
            Spacer(minLength: 8)
            Button("Select More Photos") { photos.presentLimitedPicker() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier("photos.selectMore")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct PhotosCell: View {
    let model: LibraryModel
    let index: Int
    let edge: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var photos: PhotosLibrary { model.photos }

    var body: some View {
        let asset = photos.asset(at: index)
        Button {
            Task { await model.openPhoto(at: index) }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        Color(uiColor: .secondarySystemFill)
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .bottom) { badges(asset) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { photoMenu(asset) }
        .accessibilityLabel("Photo \(index + 1)")
        .accessibilityIdentifier("photo.\(index)")
        .task(id: "\(Int(edge * displayScale))-\(photos.revision)-\(photos.currentID)") {
            photos.noteVisible(index)
            let result = await photos.thumbnail(at: index, edge: max(64, edge * displayScale))
            guard !Task.isCancelled else { return }
            image = result
        }
    }

    // MARK: Context menu

    /// Runs an engine command on this photo: registers its original with the engine first (cached after the
    /// first time), selects it, then runs `command`. `openFirst` opens it in the loupe so the result is written
    /// back to Photos when the loupe closes (anything that changes the edit).
    private func act(_ command: String, _ params: [String: Any] = [:], openFirst: Bool = false) {
        guard let local = photos.localIdentifier(at: index) else { return }
        let model = model
        let index = index
        Task { @MainActor in
            if openFirst {
                await model.openPhoto(at: index)
                model.run(command, params)
                return
            }
            do {
                let id = try await model.engineID(forAsset: local)
                model.select(id)
                model.run(command, params)
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func photoMenu(_ asset: PHAsset?) -> some View {
        Button { Task { await model.openPhoto(at: index) } } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            .accessibilityIdentifier("photos.edit")
        Button {
            Task { await photos.toggleFavorite(at: index) }
        } label: {
            Label(asset?.isFavorite == true ? "Unfavorite" : "Favorite", systemImage: asset?.isFavorite == true ? "heart.slash" : "heart")
        }
        .accessibilityIdentifier("photos.favorite")
        Menu {
            ForEach(0...5, id: \.self) { n in
                Button { act("photo.rate", ["rating": n]) } label: {
                    Label(n == 0 ? "No Rating" : "\(n) Star\(n == 1 ? "" : "s")", systemImage: n == 0 ? "star.slash" : "star")
                }
                .accessibilityIdentifier("photos.rate.\(n)")
            }
        } label: { Label("Rating", systemImage: "star") }
        Menu {
            Button { act("photo.pick") } label: { Label("Pick", systemImage: "flag.fill") }
                .accessibilityIdentifier("photos.pick")
            Button { act("photo.reject") } label: { Label("Reject", systemImage: "flag.slash.fill") }
                .accessibilityIdentifier("photos.reject")
            Button { act("photo.unflag") } label: { Label("Unflag", systemImage: "flag") }
                .accessibilityIdentifier("photos.unflag")
        } label: { Label("Flag", systemImage: "flag") }
        Divider()
        Button { act("photo.rotateLeft", openFirst: true) } label: { Label("Rotate Left", systemImage: "rotate.left") }
            .accessibilityIdentifier("photos.rotateLeft")
        Button { act("photo.rotateRight", openFirst: true) } label: { Label("Rotate Right", systemImage: "rotate.right") }
            .accessibilityIdentifier("photos.rotateRight")
        Divider()
        Button { act("develop.copy") } label: { Label("Copy Edit Settings", systemImage: "doc.on.doc") }
            .accessibilityIdentifier("photos.copySettings")
        Button { Task { await model.pasteSettings(toAssetAt: index) } } label: { Label("Paste Edit Settings", systemImage: "doc.on.clipboard") }
            .accessibilityIdentifier("photos.pasteSettings")
        Button { act("develop.reset", openFirst: true) } label: { Label("Reset Edits", systemImage: "arrow.counterclockwise") }
            .accessibilityIdentifier("photos.reset")
        Divider()
        Button { act("dialog.export") } label: { Label("Export / Share\u{2026}", systemImage: "square.and.arrow.up") }
            .accessibilityIdentifier("photos.export")
    }

    @ViewBuilder
    private func badges(_ asset: PHAsset?) -> some View {
        if let asset, asset.hasAdjustments || asset.isFavorite {
            // Kept: legibility scrim over photo content.
            HStack(spacing: 4) {
                if asset.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.white) }
                Spacer(minLength: 0)
                if asset.hasAdjustments {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("photo.edited.\(index)")
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45))
        }
    }
}
