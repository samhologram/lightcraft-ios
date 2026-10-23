import SwiftUI
@preconcurrency import LightCraftKit

/// A source the grid can show (`library.source`).
struct LibrarySourceRow: Identifiable, Hashable {
    let id: String          // accessibility suffix: "all", "recentlyAdded", … or the album id
    let title: String
    let symbol: String
    let kind: String        // library.source kind
    let albumID: UInt64?
    let count: UInt64?
    let depth: Int
    let selectable: Bool

    var params: [String: Any] {
        var p: [String: Any] = ["kind": kind]
        if let albumID { p["id"] = albumID }
        return p
    }

    static let fixed: [LibrarySourceRow] = [
        LibrarySourceRow(id: "all", title: "All Photos", symbol: "photo.on.rectangle", kind: "all", albumID: nil, count: nil, depth: 0, selectable: true),
        LibrarySourceRow(id: "recentlyAdded", title: "Recently Added", symbol: "clock", kind: "recentlyAdded", albumID: nil, count: nil, depth: 0, selectable: true),
        LibrarySourceRow(id: "picks", title: "Picks", symbol: "flag", kind: "picks", albumID: nil, count: nil, depth: 0, selectable: true),
        LibrarySourceRow(id: "recentlyDeleted", title: "Recently Deleted", symbol: "trash", kind: "recentlyDeleted", albumID: nil, count: nil, depth: 0, selectable: true),
    ]

    static func albums(_ albums: [AlbumInfo]) -> [LibrarySourceRow] {
        albums.map { a in
            LibrarySourceRow(
                id: "\(a.id)", title: a.name,
                symbol: a.kind == "smart" ? "gearshape.2" : (a.kind == "folder" ? "folder" : "rectangle.stack"),
                kind: "album", albumID: a.id, count: a.count, depth: Int(a.depth), selectable: a.kind != "folder"
            )
        }
    }

    /// Whether `state.source` (the JSON of the engine's LibrarySource) names this row. Accepts
    /// `{"kind":"album","id":3}` as well as externally tagged forms such as `{"album":3}` or `"all"`.
    func isCurrent(source json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return false }
        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "_", with: "") }
        var k = ""
        var i: UInt64?
        if let s = any as? String {
            k = norm(s)
        } else if let d = any as? [String: Any] {
            if let kind = d["kind"] as? String {
                k = norm(kind)
                i = (d["id"] as? NSNumber)?.uint64Value
            } else if let first = d.first {
                k = norm(first.key)
                i = (first.value as? NSNumber)?.uint64Value
                if i == nil, let inner = first.value as? [String: Any] { i = (inner["id"] as? NSNumber)?.uint64Value }
            }
        }
        guard k == norm(kind) else { return false }
        return albumID == nil || albumID == i
    }
}

@MainActor private func selectSource(_ row: LibrarySourceRow, model: LibraryModel) {
    model.run("library.source", row.params)
    if model.mode == .loupe { model.mode = .grid }
}

/// iPad source list: All Photos, smart sources and the albums.
struct AlbumSidebar: View {
    let model: LibraryModel

    @State private var renaming: LibrarySourceRow?
    @State private var newName = ""

    var body: some View {
        if model.samplesMode { samplesList } else { PhotosSidebar(model: model) }
    }

    private var samplesList: some View {
        List {
            Section("Samples") {
                ForEach(LibrarySourceRow.fixed) { row in sourceButton(row) }
            }
            let rows = LibrarySourceRow.albums(model.albums)
            if !rows.isEmpty {
                Section("Albums") {
                    ForEach(rows) { row in sourceButton(row) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.present("album.create")
                } label: {
                    Label("New Album", systemImage: "plus")
                }
                .accessibilityIdentifier("command.album.create")
            }
        }
        .alert("Rename Album", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let id = renaming?.albumID, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.run("album.rename", ["id": id, "name": newName])
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder
    private func sourceButton(_ row: LibrarySourceRow) -> some View {
        let current = row.isCurrent(source: model.state.source)
        Button {
            if row.selectable { selectSource(row, model: model) }
        } label: {
            HStack {
                Label {
                    Text(verbatim: row.title)
                } icon: {
                    Image(systemName: row.symbol)
                }
                Spacer(minLength: 4)
                if let count = row.count {
                    Text(verbatim: "\(count)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.leading, CGFloat(row.depth) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(current ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("album.\(row.id)")
        .contextMenu {
            if let id = row.albumID {
                Button {
                    newName = row.title
                    renaming = row
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .accessibilityIdentifier("command.album.rename")
                Button(role: .destructive) {
                    model.run("album.delete", ["id": id])
                } label: {
                    Label("Delete Album", systemImage: "trash")
                }
                .accessibilityIdentifier("command.album.delete")
            }
        }
    }
}

/// iPhone: the same sources as a menu (used in the grid's toolbar).
struct SourceMenuContent: View {
    let model: LibraryModel

    var body: some View {
        if model.samplesMode { samples } else { PhotosSourceMenuContent(model: model) }
    }

    @ViewBuilder
    private var samples: some View {
        ForEach(LibrarySourceRow.fixed) { row in item(row) }
        let rows = LibrarySourceRow.albums(model.albums)
        if !rows.isEmpty {
            Divider()
            ForEach(rows) { row in item(row) }
        }
        Divider()
        Button {
            model.present("album.create")
        } label: {
            Label("New Album…", systemImage: "plus")
        }
        .accessibilityIdentifier("command.album.create")
    }

    @ViewBuilder
    private func item(_ row: LibrarySourceRow) -> some View {
        let current = row.isCurrent(source: model.state.source)
        Button {
            if row.selectable { selectSource(row, model: model) }
        } label: {
            if current {
                Label { Text(verbatim: row.title) } icon: { Image(systemName: "checkmark") }
            } else {
                Label { Text(verbatim: row.title) } icon: { Image(systemName: row.symbol) }
            }
        }
        .disabled(!row.selectable)
        .accessibilityIdentifier("album.\(row.id)")
    }

    /// Title of the current source for the toolbar.
    static func currentTitle(model: LibraryModel) -> String {
        if !model.samplesMode { return model.photos.current?.title ?? "Photos" }
        if let row = LibrarySourceRow.fixed.first(where: { $0.isCurrent(source: model.state.source) }) { return row.title }
        if let row = LibrarySourceRow.albums(model.albums).first(where: { $0.isCurrent(source: model.state.source) }) { return row.title }
        return "Library"
    }
}

/// iPad sidebar in Photos mode: the library's sources, smart albums and albums.
struct PhotosSidebar: View {
    let model: LibraryModel

    var body: some View {
        let photos = model.photos
        List {
            section("Library", .library)
            section("Smart Albums", .smart)
            section("Albums", .album)
        }
        .listStyle(.sidebar)
        .navigationTitle("Photos")
        .accessibilityIdentifier("sidebar.photos")
        .id(photos.revision)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ group: PhotosSource.Group) -> some View {
        let rows = model.photos.sources.filter { $0.group == group }
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in sourceButton(row) }
            }
        }
    }

    private func sourceButton(_ row: PhotosSource) -> some View {
        let current = model.photos.currentID == row.id
        return Button {
            model.photos.select(row.id)
            if model.mode == .loupe { model.mode = .grid }
        } label: {
            HStack {
                Label {
                    Text(verbatim: row.title)
                } icon: {
                    Image(systemName: row.symbol)
                }
                Spacer(minLength: 4)
                if let count = row.count {
                    Text(verbatim: "\(count)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(current ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("album.\(row.id)")
    }
}

/// iPhone source menu in Photos mode.
struct PhotosSourceMenuContent: View {
    let model: LibraryModel

    var body: some View {
        let photos = model.photos
        ForEach(Array([PhotosSource.Group.library, .smart, .album].enumerated()), id: \.offset) { offset, group in
            let rows = photos.sources.filter { $0.group == group }
            if !rows.isEmpty {
                if offset > 0 { Divider() }
                ForEach(rows) { row in
                    Button {
                        photos.select(row.id)
                    } label: {
                        Label {
                            Text(verbatim: row.title)
                        } icon: {
                            Image(systemName: photos.currentID == row.id ? "checkmark" : row.symbol)
                        }
                    }
                    .accessibilityIdentifier("album.\(row.id)")
                }
            }
        }
    }
}
