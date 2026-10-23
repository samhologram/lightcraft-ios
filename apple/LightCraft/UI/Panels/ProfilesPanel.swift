import SwiftUI
@preconcurrency import LightCraftKit

/// Profile browser: camera / creative / imported profiles; tap applies one; Amount slider below.
struct ProfilesPanel: View {
    let model: LibraryModel

    private struct ProfileRow: Identifiable {
        let id: String
        let name: String
        let group: String
        let favorite: Bool
    }

    @State private var profiles: [ProfileRow] = []
    @State private var currentID = ""

    private static let amount: ControlInfo? = developControls().first { $0.id == "profile.amount" }

    private var groups: [(title: String, rows: [ProfileRow])] {
        var order: [String] = []
        var buckets: [String: [ProfileRow]] = [:]
        for r in profiles {
            let g = r.group.isEmpty ? "Profiles" : r.group
            if buckets[g] == nil { order.append(g) }
            buckets[g, default: []].append(r)
        }
        return order.map { (title: $0, rows: buckets[$0] ?? []) }
    }

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to choose a profile.")
        } else {
            VStack(spacing: 0) {
                if let amount = Self.amount {
                    DevelopSlider(model: model, control: amount)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                List {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in
                                HStack {
                                    Button {
                                        model.run("develop.profile", ["id": row.id])
                                    } label: {
                                        HStack {
                                            Text(verbatim: row.name)
                                            Spacer()
                                            if currentID == row.id {
                                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(currentID == row.id ? .isSelected : [])
                                    .accessibilityIdentifier("profile.\(row.id)")
                                    Button {
                                        model.run("profile.favorite", ["id": row.id])
                                    } label: {
                                        Image(systemName: row.favorite ? "star.fill" : "star")
                                            .foregroundStyle(row.favorite ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Favorite")
                                    .accessibilityIdentifier("command.profile.favorite.\(row.id)")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: model.state.active) { _, _ in reload() }
        }
    }

    private func reload() {
        if let list = EngineQuery.json(model, "profiles.list") as? [[String: Any]] {
            profiles = list.compactMap { p in
                guard let id = p["id"] as? String else { return nil }
                return ProfileRow(id: id, name: (p["name"] as? String) ?? id, group: (p["group"] as? String) ?? "",
                                  favorite: (p["favorite"] as? Bool) ?? false)
            }
        }
        if let id = model.state.active, let dev = EngineQuery.develop(model, id),
           let profile = dev["profile"] as? [String: Any] {
            currentID = (profile["id"] as? String) ?? ""
        } else {
            currentID = ""
        }
    }
}
