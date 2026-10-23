import SwiftUI
@preconcurrency import LightCraftKit

/// Info: the active photo's basic facts, an editable title, and every EXIF / XMP tag on demand.
struct InfoPanel: View {
    let model: LibraryModel

    private struct Tag: Identifiable {
        let id: Int
        let group: String
        let name: String
        let value: String
    }

    @State private var title = ""
    @State private var tags: [Tag] = []
    @State private var showTags = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let photo = model.activePhoto {
            List {
                Section("Title") {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit { commitTitle(photo) }
                        .accessibilityIdentifier("info.title")
                }
                Section("File") {
                    row("Name", photo.fileName)
                    row("Format", photo.format)
                    row("Size", "\(photo.width) × \(photo.height)")
                    if let captured = photo.captured { row("Captured", captured) }
                    if !photo.camera.isEmpty { row("Camera", photo.camera) }
                    if !photo.lens.isEmpty { row("Lens", photo.lens) }
                    row("Rating", photo.rating == 0 ? "None" : String(repeating: "★", count: Int(photo.rating)))
                    row("Flag", photo.flag.capitalized)
                    row("Edited", photo.edited ? "Yes" : "No")
                }
                Section {
                    DisclosureGroup("All Metadata", isExpanded: $showTags) {
                        if tags.isEmpty {
                            Text("No metadata.").foregroundStyle(.secondary)
                        }
                        ForEach(tags) { t in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: t.name).font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: t.value).font(.footnote).textSelection(.enabled)
                            }
                        }
                    }
                    .accessibilityIdentifier("info.allMetadata")
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: photo.id, initial: true) { _, _ in
                title = photo.title
                tags = []
                if showTags { loadTags(photo.id) }
            }
            .onChange(of: photo.title) { _, new in if !titleFocused { title = new } }
            .onChange(of: showTags) { _, on in if on { loadTags(photo.id) } }
            .onChange(of: titleFocused) { _, focused in if !focused { commitTitle(photo) } }
        } else {
            PanelEmptyState(title: "No Photo", symbol: "info.circle", message: "Open a photo to see its information.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(verbatim: value).textSelection(.enabled) }
    }

    private func commitTitle(_ photo: PhotoInfo) {
        guard title != photo.title else { return }
        model.run("photo.setMeta", ["ids": [photo.id], "title": title])
    }

    private func loadTags(_ id: UInt64) {
        guard let all = EngineQuery.json(model, "photo.allMetadata", ["id": id]) as? [String: Any] else { return }
        var out: [Tag] = []
        for e in (all["exif"] as? [[String: Any]]) ?? [] {
            out.append(Tag(id: out.count, group: (e["group"] as? String) ?? "", name: (e["name"] as? String) ?? "", value: (e["value"] as? String) ?? ""))
        }
        for x in (all["xmp"] as? [[String: Any]]) ?? [] {
            out.append(Tag(id: out.count, group: "XMP", name: (x["name"] as? String) ?? "", value: (x["value"] as? String) ?? ""))
        }
        tags = out
    }
}
