import SwiftUI
@preconcurrency import LightCraftKit

/// Presets: the library's presets by group; tap applies one to the selection.
struct PresetsPanel: View {
    let model: LibraryModel

    private struct PresetRow: Identifiable {
        let id: String
        let name: String
        let group: String
        let favorite: Bool
        let builtin: Bool
    }

    @State private var presets: [PresetRow] = []
    @State private var query = ""

    private var groups: [(title: String, rows: [PresetRow])] {
        let q = query.lowercased()
        let rows = presets.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        var order: [String] = []
        var buckets: [String: [PresetRow]] = [:]
        for r in rows {
            let g = r.group.isEmpty ? "Presets" : r.group
            if buckets[g] == nil { order.append(g) }
            buckets[g, default: []].append(r)
        }
        let favs = rows.filter(\.favorite)
        var out: [(String, [PresetRow])] = []
        if !favs.isEmpty { out.append(("Favorites", favs)) }
        out += order.map { ($0, buckets[$0] ?? []) }
        return out.map { (title: $0.0, rows: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search presets", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("presets.search")
                Button {
                    model.present("preset.create")
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(model.activePhoto == nil)
                .accessibilityIdentifier("command.preset.create")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if presets.isEmpty {
                PanelEmptyState(title: "No Presets", symbol: "wand.and.stars", message: "Create a preset from the current edit.")
            } else {
                List {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in
                                HStack {
                                    Button {
                                        model.run("preset.apply", ["id": row.id])
                                    } label: {
                                        Text(verbatim: row.name)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("preset.\(row.id)")
                                    Button {
                                        model.run("preset.favorite", ["id": row.id, "favorite": !row.favorite])
                                    } label: {
                                        Image(systemName: row.favorite ? "star.fill" : "star")
                                            .foregroundStyle(row.favorite ? Color.yellow : Color.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Favorite")
                                    .accessibilityIdentifier("command.preset.favorite.\(row.id)")
                                }
                                .swipeActions {
                                    if !row.builtin {
                                        Button(role: .destructive) {
                                            model.run("preset.delete", ["id": row.id])
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .accessibilityIdentifier("command.preset.delete.\(row.id)")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
    }

    private func reload() {
        guard let list = EngineQuery.json(model, "presets.list") as? [[String: Any]] else {
            presets = []
            return
        }
        presets = list.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            return PresetRow(
                id: id,
                name: (p["name"] as? String) ?? id,
                group: (p["group"] as? String) ?? "",
                favorite: (p["favorite"] as? Bool) ?? false,
                builtin: (p["builtin"] as? Bool) ?? false
            )
        }
    }
}
