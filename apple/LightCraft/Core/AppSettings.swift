import Foundation
import UIKit

/// Typed access to the user settings and launch arguments.
enum AppSettings {
    enum Key {
        static let thumbSize = "thumbSize"
        static let jpegQuality = "jpegQuality"
        static let inspectorVisible = "inspectorVisible"
        static let panelLayout = "panelLayout"
        static let lastPanel = "lastPanel"
    }

    enum Default {
        static let thumbSize = 160.0
        static let jpegQuality = 0.9
    }

    static let thumbSizeRange: ClosedRange<Double> = 80...360

    /// Launch argument that seeds new libraries with the engine's procedural demo photos.
    static let demoArgument = "-LightCraftDemo"

    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains(demoArgument) }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.thumbSize: Default.thumbSize,
            Key.jpegQuality: Default.jpegQuality,
            Key.inspectorVisible: true,
        ])
    }

    static var thumbSize: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Key.thumbSize)
            return v > 0 ? min(max(v, thumbSizeRange.lowerBound), thumbSizeRange.upperBound) : Default.thumbSize
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.thumbSize) }
    }

    static var jpegQuality: Double {
        let v = UserDefaults.standard.double(forKey: Key.jpegQuality)
        return v > 0 ? min(max(v, 0.05), 1) : Default.jpegQuality
    }

    /// The inspector starts open on iPad (it is a sheet on iPhone, which must not pop up by itself), and
    /// always so in demo / UI-test launches, so a run never depends on what the previous one left behind.
    static var initialInspectorVisible: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        return isDemo ? true : inspectorVisible
    }

    static var inspectorVisible: Bool {
        get { UserDefaults.standard.object(forKey: Key.inspectorVisible) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.inspectorVisible) }
    }
}

// MARK: Panels (remembered across launches; demo / UI-test launches always start from the defaults)

extension AppSettings {
    /// The iPad inspector arrangement (order, visible, collapsed) as JSON in UserDefaults.
    static var panelLayout: PanelLayout {
        get {
            guard !isDemo,
                  let data = UserDefaults.standard.data(forKey: Key.panelLayout),
                  let layout = try? JSONDecoder().decode(PanelLayout.self, from: data) else { return .standard }
            return layout.normalized()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: Key.panelLayout) }
        }
    }

    /// The panel that was in front last.
    static var lastPanel: Panel {
        get {
            guard !isDemo, let raw = UserDefaults.standard.string(forKey: Key.lastPanel), let p = Panel(rawValue: raw) else { return .edit }
            return p
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.lastPanel) }
    }
}
