import SwiftUI
@preconcurrency import LightCraftKit

/// A cached engine thumbnail that fills its frame (reloads when the photo's edit history changes).
struct ThumbnailView: View {
    let model: LibraryModel
    let id: UInt64
    let edge: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    private struct Key: Hashable {
        let id: UInt64
        let pixels: Int
        let history: UInt64
    }

    private var key: Key {
        Key(id: id, pixels: max(64, Int((edge * displayScale).rounded())), history: model.state.historyId)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: key) {
            let k = key
            if let result = await model.thumbnail(k.id, edge: k.pixels) {
                image = result
            }
        }
    }
}
