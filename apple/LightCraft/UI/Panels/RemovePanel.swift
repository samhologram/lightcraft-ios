import SwiftUI
@preconcurrency import LightCraftKit

/// Remove: spot removal / healing. The list of spots of the active photo, automatic finders, and the
/// overlay mode. Spots themselves are placed on the photo with the Remove tool.
struct RemovePanel: View {
    let model: LibraryModel

    private struct SpotRow: Identifiable {
        let id: Int
        let mode: String
        let size: Double
    }

    @State private var spots: [SpotRow] = []

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to remove blemishes.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Spots").font(.headline)
                    if spots.isEmpty {
                        Text("No spots yet. Use Find in the panel header, or place spots with the Remove tool on the photo.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(spots) { spot in
                        HStack {
                            Button {
                                model.run("spot.select", ["index": spot.id])
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: "\(spot.mode.capitalized) \(spot.id + 1)").font(.subheadline.weight(.medium))
                                    Text(verbatim: "Size \(Int((spot.size * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("spot.\(spot.id)")
                            Button {
                                model.run("spot.delete", ["index": spot.id])
                            } label: {
                                Image(systemName: "trash").frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Delete spot")
                            .accessibilityIdentifier("command.spot.delete.\(spot.id)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
            }
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: model.state.active) { _, _ in reload() }
        }
    }

    private func reload() {
        guard let id = model.state.active,
              let dev = EngineQuery.develop(model, id),
              let list = dev["spots"] as? [[String: Any]] else {
            spots = []
            return
        }
        spots = list.enumerated().map { i, s in
            SpotRow(id: i, mode: (s["mode"] as? String) ?? "remove", size: jsonNumber(s["size"]) ?? 0)
        }
    }
}
