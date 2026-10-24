import SwiftUI

// iPadOS menu bar, generated from the desktop menu layout (`desktopMenuLayout()`): File, Edit, View, Photo,
// Window, Help, in that order. File / Edit / View / Window / Help extend the system menus; Photo is custom
// (custom menus appear after View). There is no "Tools" or "All Commands" menu. Every item acts on the focused
// scene's model (`@FocusedValue(\.libraryModel)`) and carries `command.<id>` as accessibility identifier.

// MARK: - Layout

/// One entry of a generated menu.
struct LayoutEntry: Identifiable {
    enum Kind {
        case command(String)
        case separator
        case submenu(String, [String])
        case rating, flag, colorLabel
    }

    let id: Int
    let kind: Kind
}

@MainActor
enum MenuLayout {
    /// Desktop registry entries that are reached another way (expanded submenus or other UI).
    private static let hidden: Set<String> = [
        "photo.rate", "photo.flag", "photo.pick", "photo.reject", "photo.unflag", "photo.label",
        "library.sort", "library.shuffle", "album.addPhotos", "album.create", "library.import", "preset.create",
    ]
    private static let last: Set<String> = ["app.quit"]
    /// Shortcuts the system or the document scene already uses.
    private static let reserved: Set<String> = ["cmd+n", "cmd+o", "cmd+w", "cmd+q", "cmd+h", "cmd+m", "cmd+p", "cmd+s", "cmd+c", "cmd+x", "cmd+v", "cmd+z", "cmd+shift+z", "cmd+,"]

    /// A command shows in a menu when this platform can run it.
    static func isVisible(_ id: String) -> Bool {
        let catalog = CommandCatalog.shared
        guard catalog.isKnown(id) else { return false }
        return catalog.isUI(id) ? LibraryModel.implementsUI(id) : catalog.isAvailable(id)
    }

    /// Menu entries of the top-level menu `title`, in desktop order, without `skipping` ids.
    static func entries(for title: String, skipping: Set<String> = []) -> [LayoutEntry] {
        let catalog = CommandCatalog.shared
        guard let section = catalog.menus.first(where: { $0.title == title }) else { return [] }
        var items: [LayoutEntry.Kind] = []
        var used = Set<String>(skipping)
        var knownSubmenus = Set<String>()
        for slot in section.items {
            if slot == "---" {
                items.append(.separator)
            } else if slot.hasPrefix("@") {
                let name = String(slot.dropFirst())
                knownSubmenus.insert(name)
                switch name {
                case "Set Rating": items.append(.rating)
                case "Set Flag": items.append(.flag)
                case "Set Color Label": items.append(.colorLabel)
                default:
                    let ids = catalog.commandIDs(menuPath: [title, name]).filter { isVisible($0) && !skipping.contains($0) }
                    if !ids.isEmpty { items.append(.submenu(name, ids)) }
                }
            } else if !used.contains(slot), isVisible(slot), !last.contains(slot) {
                used.insert(slot)
                items.append(.command(slot))
            }
        }
        // Everything else that names this menu and the layout does not list.
        var extra: [LayoutEntry.Kind] = []
        for info in catalog.commands where info.menu.first == title && !used.contains(info.id) && !hidden.contains(info.id) {
            guard isVisible(info.id), !last.contains(info.id) else { continue }
            if info.menu.count == 1 {
                extra.append(.command(info.id))
            } else if info.menu.count == 2, !knownSubmenus.contains(info.menu[1]) {
                knownSubmenus.insert(info.menu[1])
                let ids = catalog.commandIDs(menuPath: info.menu).filter { isVisible($0) && !hidden.contains($0) }
                if !ids.isEmpty { extra.append(.submenu(info.menu[1], ids)) }
            }
        }
        if !extra.isEmpty { items.append(.separator); items.append(contentsOf: extra) }
        return tidy(items).enumerated().map { LayoutEntry(id: $0.offset, kind: $0.element) }
    }

    /// Drops leading, trailing and doubled separators.
    private static func tidy(_ items: [LayoutEntry.Kind]) -> [LayoutEntry.Kind] {
        var out: [LayoutEntry.Kind] = []
        for item in items {
            if case .separator = item {
                if out.isEmpty { continue }
                if case .separator = out[out.count - 1] { continue }
            }
            out.append(item)
        }
        while let tail = out.last, case .separator = tail { out.removeLast() }
        return out
    }

    /// Keyboard shortcuts by command id: the first command to ask for a combination gets it; combinations the
    /// system owns, and Escape / Return on their own, are never taken.
    static let shortcuts: [String: KeyboardShortcut] = {
        var out: [String: KeyboardShortcut] = [:]
        var taken = reserved
        let catalog = CommandCatalog.shared
        var ids: [String] = []
        for section in catalog.menus { ids.append(contentsOf: section.items.filter { !$0.hasPrefix("@") && $0 != "---" }) }
        ids.append(contentsOf: catalog.commands.map(\.id))
        for id in ids where out[id] == nil && isVisible(id) {
            guard let shortcut = catalog.shortcut(id) else { continue }
            if shortcut.modifiers.isEmpty, shortcut.key == .escape || shortcut.key == .return { continue }
            let key = "\(shortcut.key.character)-\(shortcut.modifiers.rawValue)"
            let system = systemName(shortcut)
            if taken.contains(key) || taken.contains(system) { continue }
            taken.insert(key)
            out[id] = shortcut
        }
        return out
    }()

    private static func systemName(_ s: KeyboardShortcut) -> String {
        var name = ""
        if s.modifiers.contains(.command) { name += "cmd+" }
        if s.modifiers.contains(.control) { name += "ctrl+" }
        if s.modifiers.contains(.option) { name += "alt+" }
        if s.modifiers.contains(.shift) { name += "shift+" }
        return name + String(s.key.character)
    }
}

// MARK: - Menu items

/// One catalog command as a menu button.
struct CommandMenuItem: View {
    let model: LibraryModel?
    let id: String

    var body: some View {
        let button = Button(CommandCatalog.shared.label(id)) { model?.present(id) }
            .disabled(!(model?.isEnabled(id) ?? false))
            .accessibilityIdentifier("command.\(id)")
        if let shortcut = MenuLayout.shortcuts[id] {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}

/// The entries of one generated menu (the content of a `CommandGroup` / `CommandMenu`).
struct MenuEntries: View {
    let model: LibraryModel?
    let entries: [LayoutEntry]

    var body: some View {
        ForEach(entries) { entry in
            switch entry.kind {
            case .command(let id):
                CommandMenuItem(model: model, id: id)
            case .separator:
                Divider()
            case .submenu(let name, let ids):
                Menu(name) {
                    ForEach(ids, id: \.self) { CommandMenuItem(model: model, id: $0) }
                }
            case .rating:
                ParamSubmenu(model: model, title: "Set Rating", command: "photo.rate", key: "rating",
                             options: (0...5).map { value in
                                 ParamSubmenu.Option(tag: "\(value)", value: value,
                                                     title: value == 0 ? String(localized: "No Rating") : String(repeating: "\u{2605}", count: value))
                             })
            case .flag:
                ParamSubmenu(model: model, title: "Set Flag", command: "photo.flag", key: "flag",
                             options: [("pick", "Pick"), ("reject", "Reject"), ("none", "Unflag")].map {
                                 ParamSubmenu.Option(tag: $0.0, value: $0.0, title: String(localized: String.LocalizationValue($0.1)))
                             })
            case .colorLabel:
                ParamSubmenu(model: model, title: "Set Color Label", command: "photo.label", key: "label",
                             options: ["red", "yellow", "green", "blue", "purple", "none"].map {
                                 ParamSubmenu.Option(tag: $0, value: $0, title: $0 == "none" ? String(localized: "No Label") : $0.capitalized)
                             })
            }
        }
    }
}

/// A submenu of one parameterized command (rating 0-5, flag, color label): each option runs it directly.
struct ParamSubmenu: View {
    struct Option: Identifiable {
        let tag: String
        let value: any Sendable
        let title: String
        var id: String { tag }
    }

    let model: LibraryModel?
    let title: LocalizedStringKey
    let command: String
    let key: String
    let options: [Option]

    var body: some View {
        Menu(title) {
            ForEach(options) { option in
                Button(option.title) { model?.run(command, [key: option.value]) }
                    .accessibilityIdentifier("command.\(command).\(option.tag)")
            }
        }
        .disabled(!(model?.isEnabled(command) ?? false))
    }
}

// MARK: - Commands

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryModel) private var model

    private var undoTitle: String {
        guard let label = model?.state.undoLabel, !label.isEmpty else { return String(localized: "Undo") }
        return String(localized: "Undo") + " " + label
    }

    private var redoTitle: String {
        guard let label = model?.state.redoLabel, !label.isEmpty else { return String(localized: "Redo") }
        return String(localized: "Redo") + " " + label
    }

    // A commands builder takes at most 10 items, so the body is split in groups.
    var body: some Commands {
        fileCommands
        editCommands
        viewCommands
        photoCommands
        windowAndHelpCommands
    }

    @CommandsBuilder private var fileCommands: some Commands {
        CommandGroup(after: .newItem) {
            MenuEntries(model: model, entries: MenuLayout.entries(for: "File"))
        }
    }

    @CommandsBuilder private var editCommands: some Commands {
        // edit.undo / edit.redo replace the system group; they go through the engine history (UndoManager mirror).
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(model?.state.canUndo ?? false))
                .accessibilityIdentifier("command.edit.undo")
            Button(redoTitle) { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(model?.state.canRedo ?? false))
                .accessibilityIdentifier("command.edit.redo")
        }
        CommandGroup(after: .pasteboard) {
            MenuEntries(model: model, entries: MenuLayout.entries(for: "Edit", skipping: ["edit.undo", "edit.redo"]))
        }
    }

    @CommandsBuilder private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            MenuEntries(model: model, entries: MenuLayout.entries(for: "View"))
            Divider()
            // UI-only (no engine command): toggles the model's canvas-only flag, only with a photo open.
            Button(model?.canvasOnly == true ? String(localized: "Exit Full Screen Canvas") : String(localized: "Enter Full Screen Canvas")) {
                model?.canvasOnly.toggle()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
            .disabled(model?.mode != .loupe)
            .accessibilityIdentifier("control.fullscreen.menu")
        }
    }

    @CommandsBuilder private var photoCommands: some Commands {
        CommandMenu("Photo") {
            let entries = MenuLayout.entries(for: "Photo")
            if entries.isEmpty {
                Text("No Library")
            } else {
                MenuEntries(model: model, entries: entries)
            }
        }
    }

    @CommandsBuilder private var windowAndHelpCommands: some Commands {
        CommandGroup(after: .windowArrangement) {
            MenuEntries(model: model, entries: MenuLayout.entries(for: "Window"))
        }
        CommandGroup(after: .help) {
            MenuEntries(model: model, entries: MenuLayout.entries(for: "Help"))
        }
    }
}
