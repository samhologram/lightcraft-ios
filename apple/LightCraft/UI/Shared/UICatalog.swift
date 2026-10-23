import SwiftUI
@preconcurrency import LightCraftKit

/// One command as the UI sees it: an engine command (journaled or query) or a UI-only desktop command.
struct CatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let shortcut: String?
    let menu: [String]
    let isUI: Bool
    let isQuery: Bool
    /// The engine's params doc ("" for UI-only commands).
    let doc: String
}

struct ParsedShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
}

/// Cached view of the bridge catalogs (engine commands, UI-only commands, desktop menu layout).
@MainActor
enum UICatalog {
    static let layout: [MenuSection] = desktopMenuLayout()

    static let entries: [CatalogEntry] = {
        var out: [CatalogEntry] = []
        var seen = Set<String>()
        for c in commandCatalog() where seen.insert(c.id).inserted {
            out.append(CatalogEntry(id: c.id, label: c.label, shortcut: c.shortcut, menu: c.menu,
                                    isUI: false, isQuery: c.isQuery, doc: c.params))
        }
        for c in uiCommandCatalog() where seen.insert(c.id).inserted {
            out.append(CatalogEntry(id: c.id, label: c.label, shortcut: c.shortcut, menu: c.menu,
                                    isUI: true, isQuery: false, doc: ""))
        }
        return out
    }()

    static let byID: [String: CatalogEntry] = {
        var d: [String: CatalogEntry] = [:]
        for e in entries where d[e.id] == nil { d[e.id] = e }
        return d
    }()

    /// Commands the platform cannot run (ios-excluded-commands.txt); hidden from menus, greyed in the palette.
    static let unsupported: [String: String] = {
        var d: [String: String] = [:]
        for e in entries {
            if let reason = commandPlatformSupport(id: e.id) { d[e.id] = reason }
        }
        return d
    }()

    static func label(_ id: String) -> String { byID[id]?.label ?? id }
    static func isUI(_ id: String) -> Bool { byID[id]?.isUI ?? false }
    static func fields(_ id: String) -> [ParamField] { commandParams(id: id) }

    /// Runs a catalog command the way a menu item does: UI ids via `runUI`, engine ids via `present`
    /// (which opens the parameter sheet when the command needs input).
    static func invoke(_ id: String, model: LibraryModel) {
        if isUI(id) { model.runUI(id) } else { model.present(id) }
    }

    // MARK: Shortcuts (egui notation: "Cmd+Shift+R", "Shift+G", "E", "Escape", "Right")

    static func parseShortcut(_ text: String) -> ParsedShortcut? {
        var mods: EventModifiers = []
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var keyName = parts.removeLast()
        if keyName.isEmpty && text.hasSuffix("+") {
            keyName = "+"
            if parts.last == "" { parts.removeLast() }
        }
        for p in parts {
            switch p.lowercased() {
            case "cmd", "ctrl": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "alt", "option": mods.insert(.option)
            default: break
            }
        }
        let key: KeyEquivalent
        switch keyName.lowercased() {
        case "escape": key = .escape
        case "enter", "return": key = .return
        case "delete", "backspace": key = .delete
        case "right": key = .rightArrow
        case "left": key = .leftArrow
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "space": key = .space
        case "tab": key = .tab
        default:
            guard keyName.count == 1, let ch = keyName.lowercased().first else { return nil }
            key = KeyEquivalent(ch)
        }
        return ParsedShortcut(key: key, modifiers: mods)
    }
}

// MARK: Panels and tools (labels and symbols are UI-side; ids come from the raw values)

extension Panel {
    var uiID: String { "panel.\(rawValue)" }
    var uiTitle: String {
        let titles: [String: String] = [
            "edit": "Edit", "profiles": "Profiles", "crop": "Crop & Rotate", "remove": "Remove",
            "masking": "Masking", "redeye": "Red Eye", "presets": "Presets", "info": "Info",
            "keywords": "Keywords", "versions": "Versions", "activity": "History",
        ]
        return titles[rawValue] ?? rawValue.capitalized
    }
    var uiSymbol: String {
        let symbols: [String: String] = [
            "edit": "slider.horizontal.3", "profiles": "camera.filters", "crop": "crop.rotate",
            "remove": "bandage", "masking": "circle.lefthalf.filled", "redeye": "eye",
            "presets": "wand.and.stars", "info": "info.circle", "keywords": "tag",
            "versions": "square.on.square", "activity": "clock.arrow.circlepath",
        ]
        return symbols[rawValue] ?? "square"
    }
}

extension Tool {
    var uiID: String { "tool.\(rawValue)" }
    var uiTitle: String {
        let titles: [String: String] = [
            "brush": "Brush", "linear": "Linear Gradient", "radial": "Radial Gradient",
            "wbPicker": "White Balance", "guidedUpright": "Guided Upright",
        ]
        return titles[rawValue] ?? rawValue.capitalized
    }
    var uiSymbol: String {
        let symbols: [String: String] = [
            "brush": "paintbrush", "linear": "rectangle.split.1x2", "radial": "circle.dashed",
            "wbPicker": "eyedropper", "guidedUpright": "grid",
        ]
        return symbols[rawValue] ?? "scribble"
    }
}

/// Opens a panel the way the desktop does (`panel.<id>`), and makes sure the inspector shows it.
@MainActor func uiOpenPanel(_ panel: Panel, model: LibraryModel, toggle: Bool = false) {
    if toggle && model.activePanel == panel && model.inspectorVisible {
        model.inspectorVisible = false
        return
    }
    model.runUI(panel.uiID)
    model.activePanel = panel
    model.inspectorVisible = true
}

// MARK: Engine queries (read-only commands through the bridge)

@MainActor
enum EngineQuery {
    /// Runs a query command and decodes its JSON result; nil on any error.
    static func json(_ model: LibraryModel, _ id: String, _ params: [String: Any] = [:]) -> Any? {
        guard let body = try? JSONSerialization.data(withJSONObject: params),
              let text = String(data: body, encoding: .utf8),
              let out = try? model.handle.execute(id: id, paramsJson: text),
              let data = out.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The full DevelopSettings JSON of a photo.
    static func develop(_ model: LibraryModel, _ photo: UInt64) -> [String: Any]? {
        guard let text = try? model.handle.developJson(id: photo),
              let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

func jsonNumber(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
func jsonString(_ any: Any?) -> String? { any as? String }

// MARK: Shared modifiers

/// Glass button style that is prominent while `selected`.
struct GlassToggleStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension View {
    func glassToggle(_ selected: Bool) -> some View { modifier(GlassToggleStyle(selected: selected)) }
}

/// Wraps a panel row title + body with the standard inspector padding.
struct PanelEmptyState: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
