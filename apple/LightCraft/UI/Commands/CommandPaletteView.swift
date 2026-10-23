import SwiftUI
@preconcurrency import LightCraftKit

/// Searchable list of every engine and UI command. Disabled commands are greyed with the engine's
/// reason; choosing one closes the palette and runs it (or opens its parameter sheet).
struct CommandPaletteView: View {
    let model: LibraryModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct PaletteGroup: Identifiable {
        let title: String
        let rows: [CatalogEntry]
        var id: String { title }
    }

    private var tokens: [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private var results: [CatalogEntry] {
        let terms = tokens
        guard !terms.isEmpty else { return [] }
        var scored: [(entry: CatalogEntry, score: Int)] = []
        for e in UICatalog.entries {
            let label = e.label.lowercased()
            let path = e.menu.joined(separator: " ").lowercased()
            let id = e.id.lowercased()
            var score = 0
            var matched = true
            for t in terms {
                if label.hasPrefix(t) { score += 40 }
                else if label.contains(" " + t) { score += 30 }
                else if label.contains(t) { score += 20 }
                else if path.contains(t) { score += 10 }
                else if id.contains(t) { score += 5 }
                else { matched = false; break }
            }
            if matched { scored.append((e, score)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.label < $1.entry.label }
        return scored.prefix(200).map(\.entry)
    }

    private var groups: [PaletteGroup] {
        var order: [String] = []
        var buckets: [String: [CatalogEntry]] = [:]
        for e in UICatalog.entries {
            let title = e.menu.first ?? "Other Commands"
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(e)
        }
        let menuOrder = UICatalog.layout.map(\.title)
        let known = menuOrder.filter { buckets[$0] != nil }
        let rest = order.filter { !menuOrder.contains($0) }
        return (known + rest).map { PaletteGroup(title: $0, rows: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if tokens.isEmpty {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in PaletteRow(model: model, entry: row) { choose(row) } }
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { row in PaletteRow(model: model, entry: row) { choose(row) } }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("commandPaletteList")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search commands"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { close() }
                        .accessibilityIdentifier("palette.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func close() {
        model.showCommandPalette = false
        dismiss()
    }

    /// Close the palette, then (once its dismissal finished) invoke the command: presenting its
    /// parameter sheet straight away would collide with the dismissal.
    private func choose(_ entry: CatalogEntry) {
        let model = model
        let id = entry.id
        close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            UICatalog.invoke(id, model: model)
        }
    }
}

private struct PaletteRow: View {
    let model: LibraryModel
    let entry: CatalogEntry
    let action: () -> Void

    private var platformReason: String? { UICatalog.unsupported[entry.id] }
    private var engineReason: String? {
        entry.isUI ? nil : model.handle.disabledReason(id: entry.id)
    }
    private var reason: String? { platformReason ?? engineReason }

    var body: some View {
        let why = reason
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.label)
                        .foregroundStyle(why == nil ? Color.primary : Color.secondary)
                    Text(verbatim: entry.menu.isEmpty ? entry.id : entry.menu.joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let why {
                        Text(verbatim: why)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                if let shortcut = entry.shortcut {
                    Text(verbatim: shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(why != nil)
        .accessibilityIdentifier("command.\(entry.id)")
    }
}
