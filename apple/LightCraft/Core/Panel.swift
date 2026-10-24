import Foundation

/// The inspector panels of the loupe. `rawValue` is the suffix of the desktop `panel.<id>` command.
enum Panel: String, CaseIterable, Identifiable, Sendable, Codable {
    case edit, profiles, crop, remove, masking, redeye, presets, info, keywords, versions, activity

    var id: String { rawValue }
    /// Desktop UI command id (`panel.edit`, ...).
    var commandID: String { "panel.\(rawValue)" }

    var title: String {
        switch self {
        case .edit: String(localized: "Edit")
        case .profiles: String(localized: "Profiles")
        case .crop: String(localized: "Crop & Rotate")
        case .remove: String(localized: "Remove")
        case .masking: String(localized: "Masking")
        case .redeye: String(localized: "Red Eye")
        case .presets: String(localized: "Presets")
        case .info: String(localized: "Info")
        case .keywords: String(localized: "Keywords")
        case .versions: String(localized: "Versions")
        case .activity: String(localized: "History")
        }
    }

    var symbol: String {
        switch self {
        case .edit: "slider.horizontal.3"
        case .profiles: "camera.filters"
        case .crop: "crop.rotate"
        case .remove: "bandage"
        case .masking: "circle.dashed"
        case .redeye: "eye"
        case .presets: "square.stack"
        case .info: "info.circle"
        case .keywords: "tag"
        case .versions: "square.on.square"
        case .activity: "clock.arrow.circlepath"
        }
    }

    static func from(commandID: String) -> Panel? {
        guard commandID.hasPrefix("panel.") else { return nil }
        return Panel(rawValue: String(commandID.dropFirst("panel.".count)))
    }
}

/// Arrangement of the iPad inspector column: order, which panels are shown, which are collapsed.
/// Codable; persisted by `AppSettings.panelLayout`. Stores `hidden` (not `visible`) so a panel added in
/// a later version shows up by default.
struct PanelLayout: Codable, Equatable, Sendable {
    var order: [Panel]
    var hidden: Set<Panel>
    var collapsed: Set<Panel>

    /// Every panel shown, in desktop order; only Edit open (collapsed headers are cheap, the column stays calm).
    static let standard = PanelLayout(order: Panel.allCases, hidden: [], collapsed: Set(Panel.allCases).subtracting([.edit]))

    /// Drops duplicates and appends panels missing from `order`.
    func normalized() -> PanelLayout {
        var seen = Set<Panel>()
        var out = order.filter { seen.insert($0).inserted }
        out += Panel.allCases.filter { !seen.contains($0) }
        return PanelLayout(order: out, hidden: hidden, collapsed: collapsed)
    }

    var visiblePanels: [Panel] { order.filter { !hidden.contains($0) } }
    func isVisible(_ panel: Panel) -> Bool { !hidden.contains(panel) }
    func isCollapsed(_ panel: Panel) -> Bool { collapsed.contains(panel) }
}

/// Grid (library) or loupe (single photo).
enum Mode: String, CaseIterable, Sendable {
    case grid, loupe
}
