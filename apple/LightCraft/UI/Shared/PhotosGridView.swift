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
    }

    private var content: some View {
        VStack(spacing: 0) {
            if photos.status == .limited { limitedBanner }
            if photos.count == 0 {
                ContentUnavailableView("No Photos", systemImage: "photo", description: Text("There are no photos in this album."))
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
        .contextMenu {
            Button {
                Task { await photos.toggleFavorite(at: index) }
            } label: {
                Label(asset?.isFavorite == true ? "Unfavorite" : "Favorite", systemImage: asset?.isFavorite == true ? "heart.slash" : "heart")
            }
            .accessibilityIdentifier("photos.favorite")
        }
        .accessibilityLabel("Photo \(index + 1)")
        .accessibilityIdentifier("photo.\(index)")
        .task(id: "\(Int(edge * displayScale))-\(photos.revision)-\(photos.currentID)") {
            image = await photos.thumbnail(at: index, edge: max(64, edge * displayScale))
        }
    }

    @ViewBuilder
    private func badges(_ asset: PHAsset?) -> some View {
        if let asset, asset.hasAdjustments || asset.isFavorite {
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
