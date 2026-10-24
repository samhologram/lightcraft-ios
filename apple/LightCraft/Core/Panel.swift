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

/// A stack in the inspector dock. Opened panels stay in its tabs until explicitly closed.
struct PanelDockGroup: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var tabs: [Panel]
    var selected: Panel
    var collapsed: Bool

    init(id: UUID = UUID(), tabs: [Panel], selected: Panel? = nil, collapsed: Bool = false) {
        self.id = id
        self.tabs = tabs
        self.selected = selected.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs[0]
        self.collapsed = collapsed
    }
}

/// Persisted PhotoCraft-style dock layout. Legacy section layouts are migrated on decode.
struct PanelLayout: Codable, Equatable, Sendable {
    var groups: [PanelDockGroup]

    static let standard = PanelLayout(groups: [
        PanelDockGroup(tabs: [.edit, .profiles, .presets]),
        PanelDockGroup(tabs: [.crop, .remove], collapsed: true),
        PanelDockGroup(tabs: [.masking, .redeye], collapsed: true),
        PanelDockGroup(tabs: [.info, .keywords], collapsed: true),
        PanelDockGroup(tabs: [.versions, .activity], collapsed: true),
    ])

    /// Drops duplicate tabs and repairs a selected panel removed by a prior version.
    func normalized() -> PanelLayout {
        var seen = Set<Panel>()
        var out: [PanelDockGroup] = []
        for var group in groups {
            group.tabs = group.tabs.filter { seen.insert($0).inserted }
            guard !group.tabs.isEmpty else { continue }
            if !group.tabs.contains(group.selected) { group.selected = group.tabs[0] }
            out.append(group)
        }
        return PanelLayout(groups: out)
    }

    func isVisible(_ panel: Panel) -> Bool { groups.contains { $0.tabs.contains(panel) } }
    func groupIndex(containing panel: Panel) -> Int? { groups.firstIndex { $0.tabs.contains(panel) } }

    private enum CodingKeys: String, CodingKey { case groups, order, hidden, collapsed }

    init(groups: [PanelDockGroup]) { self.groups = groups }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groups, forKey: .groups)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let groups = try container.decodeIfPresent([PanelDockGroup].self, forKey: .groups) {
            self = PanelLayout(groups: groups).normalized()
            return
        }
        let order = try container.decodeIfPresent([Panel].self, forKey: .order) ?? Panel.allCases
        let hidden = try container.decodeIfPresent(Set<Panel>.self, forKey: .hidden) ?? []
        let collapsed = try container.decodeIfPresent(Set<Panel>.self, forKey: .collapsed) ?? []
        let visible = order.filter { !hidden.contains($0) }
        let pairs: [[Panel]] = [[.edit, .profiles, .presets], [.crop, .remove], [.masking, .redeye],
                                [.info, .keywords], [.versions, .activity]]
        groups = pairs.compactMap { pair in
            let tabs = pair.filter { visible.contains($0) }
            guard !tabs.isEmpty else { return nil }
            let selected = tabs.first { !collapsed.contains($0) } ?? tabs[0]
            return PanelDockGroup(tabs: tabs, selected: selected, collapsed: collapsed.contains(selected))
        }
    }
}

/// Grid (library) or loupe (single photo).
enum Mode: String, CaseIterable, Sendable {
    case grid, loupe
}
