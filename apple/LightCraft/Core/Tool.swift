import Foundation

/// Canvas tools. `rawValue` is the suffix of the desktop `tool.<id>` command.
enum Tool: String, CaseIterable, Identifiable, Sendable {
    case brush, linear, radial, wbPicker, guidedUpright

    var id: String { rawValue }
    var commandID: String { "tool.\(rawValue)" }

    var title: String {
        switch self {
        case .brush: String(localized: "Brush")
        case .linear: String(localized: "Linear Gradient")
        case .radial: String(localized: "Radial Gradient")
        case .wbPicker: String(localized: "White Balance Selector")
        case .guidedUpright: String(localized: "Guided Upright")
        }
    }

    var symbol: String {
        switch self {
        case .brush: "paintbrush"
        case .linear: "line.diagonal"
        case .radial: "circle.circle"
        case .wbPicker: "eyedropper"
        case .guidedUpright: "perspective"
        }
    }

    /// The panel the tool lives in (it opens when the tool is chosen).
    var panel: Panel? {
        switch self {
        case .brush, .linear, .radial: .masking
        case .wbPicker: .edit
        case .guidedUpright: .crop
        }
    }

    static func from(commandID: String) -> Tool? {
        guard commandID.hasPrefix("tool.") else { return nil }
        return Tool(rawValue: String(commandID.dropFirst("tool.".count)))
    }
}
