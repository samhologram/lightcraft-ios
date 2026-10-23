import SwiftUI
@preconcurrency import LightCraftKit

/// Horizontal strip of the photos in view; tapping one makes it the active photo.
struct Filmstrip: View {
    let model: LibraryModel
    var height: CGFloat = 64

    var body: some View {
        if model.samplesMode { samples } else { PhotosFilmstrip(model: model, height: height) }
    }

    private var samples: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(model.visible, id: \.self) { id in
                        let active = model.state.active == id
                        Button {
                            model.select(id)
                        } label: {
                            ThumbnailView(model: model, id: id, edge: height)
                                .frame(width: height, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(id)
                        .accessibilityIdentifier("filmstrip.\(id)")
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.state.active, initial: true) { _, new in
                if let new { withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .frame(height: height + 8)
        // Stays inside its column: the iPad inspector floats over the trailing edge.
        .background(.bar, ignoresSafeAreaEdges: [])
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmstrip")
    }
}

/// The filmstrip in Photos mode: the current source's photos; tapping one opens it.
private struct PhotosFilmstrip: View {
    let model: LibraryModel
    let height: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let photos = model.photos
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(0..<photos.count, id: \.self) { index in
                        let active = model.openIndex == index
                        Button {
                            Task { await model.openPhoto(at: index) }
                        } label: {
                            FilmstripThumb(photos: photos, index: index, edge: height * displayScale)
                                .frame(width: height, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityIdentifier("filmstrip.\(index)")
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.openIndex, initial: true) { _, new in
                if let new { withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .frame(height: height + 8)
        .background(.bar, ignoresSafeAreaEdges: [])
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmstrip")
    }
}

private struct FilmstripThumb: View {
    let photos: PhotosLibrary
    let index: Int
    let edge: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: "\(photos.revision)-\(photos.currentID)") {
            image = await photos.thumbnail(at: index, edge: max(64, edge))
        }
    }
}
