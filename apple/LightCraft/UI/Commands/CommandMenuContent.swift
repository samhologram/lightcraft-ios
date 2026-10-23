import SwiftUI
@preconcurrency import LightCraftKit

/// Renders the catalog commands under a menu path (e.g. `["Photo"]`, `["Photo", "Set Flag"]`) in the
/// desktop's order: the layout's items first (separators and submenus included), then any commands the
/// layout does not list. Use inside a `Menu`, `contextMenu` or menu bar `Commands`.
struct CommandMenuContent: View {
    let model: LibraryModel
    let path: [String]

    private enum Item {
        case command(CatalogEntry)
        case divider
        case submenu(String)
    }

    private func visible(_ e: CatalogEntry) -> Bool { UICatalog.unsupported[e.id] == nil }

    private var items: [Item] {
        var out: [Item] = []
        var used = Set<String>()
        var subs = Set<String>()
        if path.count == 1, let section = UICatalog.layout.first(where: { $0.title == path[0] }) {
            for raw in section.items {
                if raw == "---" {
                    if case .divider? = out.last { continue }
                    if !out.isEmpty { out.append(.divider) }
                } else if raw.hasPrefix("@") {
                    let name = String(raw.dropFirst())
                    out.append(.submenu(name))
                    subs.insert(name)
                } else if let e = UICatalog.byID[raw], visible(e) {
                    out.append(.command(e))
                    used.insert(e.id)
                }
            }
        }
        for e in UICatalog.entries where !used.contains(e.id) && e.menu == path && visible(e) {
            out.append(.command(e))
        }
        for e in UICatalog.entries where e.menu.count > path.count && Array(e.menu.prefix(path.count)) == path && visible(e) {
            let name = e.menu[path.count]
            if subs.insert(name).inserted { out.append(.submenu(name)) }
        }
        while case .divider? = out.last { out.removeLast() }
        return out
    }

    private func hasContent(_ sub: String) -> Bool {
        let p = path + [sub]
        return UICatalog.entries.contains { e in
            visible(e) && e.menu.count >= p.count && Array(e.menu.prefix(p.count)) == p
        }
    }

    var body: some View {
        let list = items
        ForEach(Array(list.enumerated()), id: \.offset) { _, item in
            switch item {
            case .command(let e):
                CommandMenuButton(model: model, entry: e)
            case .divider:
                Divider()
            case .submenu(let name):
                if hasContent(name) {
                    Menu(name) {
                        CommandMenuContent(model: model, path: path + [name])
                    }
                    .accessibilityIdentifier("menu.\(path.joined(separator: ".")).\(name)")
                }
            }
        }
    }
}

/// A menu item for one catalog command (`command.<id>`).
struct CommandMenuButton: View {
    let model: LibraryModel
    let entry: CatalogEntry

    var body: some View {
        Button {
            UICatalog.invoke(entry.id, model: model)
        } label: {
            Text(verbatim: entry.label)
        }
        .disabled(!entry.isUI && !model.isEnabled(entry.id))
        .accessibilityIdentifier("command.\(entry.id)")
    }
}
