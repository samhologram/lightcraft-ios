import SwiftUI
@preconcurrency import LightCraftKit

/// The data-driven command system. Wraps the engine catalog (`commandCatalog()`), the desktop UI-only
/// commands (`uiCommandCatalog()`) and the desktop menu order (`desktopMenuLayout()`). Menus, the command
/// palette and parameter sheets are generated from this, so new engine commands appear without Swift changes.
@MainActor
final class CommandCatalog {
    static let shared = CommandCatalog()

    let commands: [CommandInfo]
    let uiCommands: [UiCommandInfo]
    /// Desktop menu bar order: `items` are command ids, "---" and "@Submenu" placeholders.
    let menus: [MenuSection]

    private let engineByID: [String: CommandInfo]
    private let uiByID: [String: UiCommandInfo]
    private var paramCache: [String: [ParamField]] = [:]
    private var supportCache: [String: String?] = [:]

    private init() {
        let engine = commandCatalog()
        let ui = uiCommandCatalog()
        commands = engine
        uiCommands = ui
        menus = desktopMenuLayout()
        engineByID = Dictionary(engine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        uiByID = Dictionary(ui.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Lookups

    func command(_ id: String) -> CommandInfo? { engineByID[id] }
    func uiCommand(_ id: String) -> UiCommandInfo? { uiByID[id] }
    func isUI(_ id: String) -> Bool { engineByID[id] == nil && uiByID[id] != nil }
    func isKnown(_ id: String) -> Bool { engineByID[id] != nil || uiByID[id] != nil }

    func label(_ id: String) -> String { engineByID[id]?.label ?? uiByID[id]?.label ?? id }

    /// Queries do not journal (no undo step).
    func isQuery(_ id: String) -> Bool { engineByID[id]?.isQuery ?? false }

    func shortcut(_ id: String) -> KeyboardShortcut? {
        guard let text = engineByID[id]?.shortcut ?? uiByID[id]?.shortcut else { return nil }
        return Self.parseShortcut(text)
    }

    func shortcutText(_ id: String) -> String? { engineByID[id]?.shortcut ?? uiByID[id]?.shortcut }

    func params(for id: String) -> [ParamField] {
        if let cached = paramCache[id] { return cached }
        let fields = commandParams(id: id)
        paramCache[id] = fields
        return fields
    }

    /// False for commands that make no sense on iOS (`ios-excluded-commands.txt`).
    func isAvailable(_ id: String) -> Bool {
        if let cached = supportCache[id] { return cached == nil }
        let reason = commandPlatformSupport(id: id)
        supportCache[id] = .some(reason)
        return reason == nil
    }

    /// True when running the command should first ask for parameters.
    func needsSheet(_ id: String) -> Bool {
        guard let info = engineByID[id] else { return false }
        if info.label.hasSuffix("\u{2026}") || info.label.hasSuffix("...") { return true }
        return params(for: id).contains { !$0.key.isEmpty && !$0.isOptional && $0.kind != "ids" }
    }

    /// Commands (engine, then UI-only) whose menu path is exactly `path`, in catalog order.
    func commandIDs(menuPath path: [String]) -> [String] {
        commands.filter { $0.menu == path }.map(\.id) + uiCommands.filter { $0.menu == path }.map(\.id)
    }

    // MARK: Shortcut parsing

    /// Parses egui notation: "Cmd+Shift+R", "Shift+G", "E", "=", "Escape". Returns nil for function keys and
    /// anything SwiftUI cannot express.
    nonisolated static func parseShortcut(_ text: String) -> KeyboardShortcut? {
        // "Cmd++" ends in a literal "+": split on the last separator only when a key follows it.
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "", parts.count >= 2 {
            parts.removeLast()
            parts[parts.count - 1] = "+"
        }
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        var modifiers: EventModifiers = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command", "meta", "ctrl+cmd": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "option", "opt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        let key: KeyEquivalent
        switch keyName.lowercased() {
        case "backspace": key = .delete
        case "delete": key = .deleteForward
        case "enter", "return": key = .return
        case "tab": key = .tab
        case "space": key = .space
        case "esc", "escape": key = .escape
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        default:
            guard keyName.count == 1, let ch = keyName.lowercased().first else { return nil }
            key = KeyEquivalent(ch)
        }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    /// "Cmd+Shift+R" -> a symbol string for the palette ("\u{2318}\u{21E7}R").
    nonisolated static func display(_ text: String) -> String {
        text.split(separator: "+", omittingEmptySubsequences: false).map { part -> String in
            switch part.lowercased() {
            case "cmd": "\u{2318}"
            case "shift": "\u{21E7}"
            case "alt": "\u{2325}"
            case "ctrl": "\u{2303}"
            case "backspace": "\u{232B}"
            case "delete": "\u{2326}"
            case "enter": "\u{21A9}"
            case "escape": "\u{238B}"
            default: String(part).uppercased()
            }
        }.joined()
    }
}
