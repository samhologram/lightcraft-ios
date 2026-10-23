import Foundation

/// The inspector panels of the loupe. `rawValue` is the suffix of the desktop `panel.<id>` command.
enum Panel: String, CaseIterable, Identifiable, Sendable {
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

/// Grid (library) or loupe (single photo).
enum Mode: String, CaseIterable, Sendable {
    case grid, loupe
}
