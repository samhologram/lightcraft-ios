import SwiftUI
@preconcurrency import LightCraftKit

/// Keywords: the active photo's keywords (tap to remove), an entry field, and the library's keywords.
struct KeywordsPanel: View {
    let model: LibraryModel

    @State private var current: [String] = []
    @State private var library: [String] = []
    @State private var entry = ""

    private var suggestions: [String] {
        let q = entry.lowercased()
        return library.filter { !current.contains($0) && (q.isEmpty || $0.lowercased().contains(q)) }.prefix(60).map { $0 }
    }

    var body: some View {
        if let photo = model.activePhoto {
            List {
                Section("Add") {
                    HStack {
                        TextField("New keyword", text: $entry)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { add(entry, photo.id) }
                            .accessibilityIdentifier("keywords.entry")
                        Button {
                            add(entry, photo.id)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add keyword")
                        .accessibilityIdentifier("command.photo.setMeta")
                    }
                }
                Section("On This Photo") {
                    if current.isEmpty {
                        Text("No keywords.").foregroundStyle(.secondary)
                    }
                    ForEach(current, id: \.self) { k in
                        HStack {
                            Text(verbatim: k)
                            Spacer()
                            Button {
                                model.run("photo.setMeta", ["ids": [photo.id], "removeKeywords": [k]])
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(k)")
                            .accessibilityIdentifier("command.photo.setMeta.removeKeyword.\(k)")
                        }
                    }
                }
                if !suggestions.isEmpty {
                    Section("Library Keywords") {
                        ForEach(suggestions, id: \.self) { k in
                            Button { add(k, photo.id) } label: {
                                Text(verbatim: k).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("keyword.\(k)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: photo.id) { _, _ in reload() }
        } else {
            PanelEmptyState(title: "No Photo", symbol: "tag", message: "Open a photo to edit its keywords.")
        }
    }

    private func add(_ text: String, _ id: UInt64) {
        let k = text.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return }
        model.run("photo.setMeta", ["ids": [id], "addKeywords": [k]])
        entry = ""
    }

    private func reload() {
        if let m = EngineQuery.json(model, "photo.copyMetadata") as? [String: Any] {
            if let list = m["keywords"] as? [String] {
                current = list
            } else if let list = m["keywords"] as? [[String: Any]] {
                current = list.compactMap { $0["name"] as? String }
            } else {
                current = []
            }
        } else {
            current = []
        }
        if let tree = EngineQuery.json(model, "keyword.list") as? [[String: Any]] {
            var flat: [String] = []
            func walk(_ nodes: [[String: Any]]) {
                for n in nodes {
                    if let path = n["path"] as? String { flat.append(path) }
                    if let kids = n["children"] as? [[String: Any]] { walk(kids) }
                }
            }
            walk(tree)
            library = flat
        }
    }
}
