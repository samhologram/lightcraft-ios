import SwiftUI
@preconcurrency import LightCraftKit

/// Star rating and pick / reject flags for the active photo (the engine acts on the selection,
/// which always contains the active photo in the loupe).
struct RatingFlagBar: View {
    let model: LibraryModel
    var compact = false

    private var photo: PhotoInfo? { model.activePhoto }

    var body: some View {
        HStack(spacing: compact ? 4 : 10) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        model.run("photo.rate", ["rating": (photo?.rating == UInt32(n)) ? 0 : n])
                    } label: {
                        Image(systemName: (photo?.rating ?? 0) >= UInt32(n) ? "star.fill" : "star")
                            .foregroundStyle((photo?.rating ?? 0) >= UInt32(n) ? Color.yellow : Color.secondary)
                            .frame(minWidth: 30, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                    .accessibilityIdentifier("command.photo.rate.\(n)")
                }
            }
            Divider().frame(height: 22)
            HStack(spacing: 2) {
                flagButton("photo.pick", "Pick", "flag.fill", .green, active: photo?.flag == "pick")
                flagButton("photo.reject", "Reject", "flag.slash.fill", .red, active: photo?.flag == "reject")
                flagButton("photo.unflag", "Unflag", "flag", .secondary, active: photo?.flag == "none")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .capsule)
        .disabled(photo == nil)
    }

    private func flagButton(_ id: String, _ title: String, _ symbol: String, _ tint: Color, active: Bool) -> some View {
        Button {
            model.run(id)
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(active ? tint : Color.secondary)
                .frame(minWidth: 34, minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("command.\(id)")
    }
}
