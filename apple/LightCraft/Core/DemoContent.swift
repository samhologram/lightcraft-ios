import Foundation

/// Launch-argument driven demo (`-LightCraftDemo`) used by the screenshot pipeline and the UI tests.
///
/// The engine has no seed command: `LightCraftDocument` reopens an empty library with `seedDemo: true`
/// before the model is created. This type then makes a few edits through the same commands the UI uses,
/// so the grid and loupe show variety, and finally raises the `demoReady` marker (`isDemoReady`).
@MainActor
enum DemoContent {
    nonisolated static var isEnabled: Bool { AppSettings.isDemo }

    /// Steps that failed, for the log. Failures never surface as alerts in demo mode.
    private(set) static var failures: [String] = []

    static func seed(_ model: LibraryModel) async {
        model.refresh()
        let ids = model.visible
        if let first = ids.first {
            model.select(first)
            // Look: warm, lifted shadows, a bit of punch.
            step(model, "develop.set", ["values": [
                "light.exposure": 0.45, "light.contrast": 18.0, "light.shadows": 30.0,
                "color.vibrance": 25.0, "effects.clarity": 12.0,
            ]])
            step(model, "photo.rate", ["rating": 5, "ids": [first]])
            step(model, "photo.flag", ["flag": "pick", "ids": [first]])
        }
        if ids.count > 1 {
            let second = ids[1]
            step(model, "develop.set", ["values": ["light.exposure": -0.35, "color.saturation": -30.0], "ids": [second]])
            step(model, "photo.rate", ["rating": 3, "ids": [second]])
        }
        if ids.count > 2 {
            step(model, "photo.rate", ["rating": 4, "ids": [ids[2]]])
            step(model, "photo.flag", ["flag": "reject", "ids": [ids[2]]])
        }
        if let first = ids.first { model.select(first) }
        model.lastError = nil
        model.refresh()
        // Marker for UI tests, raised after the thumbnails of the first screen could start loading.
        model.isDemoReady = true
    }

    private static func step(_ model: LibraryModel, _ id: String, _ params: [String: Any]) {
        if model.execute(id, params) == nil {
            failures.append("\(id): \(model.lastError ?? "failed")")
            model.lastError = nil
        }
    }
}
