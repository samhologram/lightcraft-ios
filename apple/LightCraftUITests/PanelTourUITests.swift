import XCTest

/// Opens every panel (`panel.<id>`) through the real UI, acts on its first controls, screenshots it
/// and returns to a usable state. Only a crash fails; misses are in the `-tour-summary` attachment.
@MainActor
final class PanelTourUITests: TourTestCase {
    func testPanelsPortrait() throws { try tour(landscape: false) }
    func testPanelsLandscape() throws { try tour(landscape: true) }

    private enum Kind { case tap, slide, type }
    private struct Step { let prefix: String; let kind: Kind }

    private static let steps: [String: [Step]] = [
        "edit": [Step(prefix: "control.", kind: .slide), Step(prefix: "command.develop.auto", kind: .tap)],
        "profiles": [Step(prefix: "profile.", kind: .tap)],
        "crop": [Step(prefix: "crop.aspect.", kind: .tap), Step(prefix: "command.crop.autoStraighten", kind: .tap),
                 Step(prefix: "command.photo.rotateLeft", kind: .tap), Step(prefix: "command.crop.reset", kind: .tap)],
        "remove": [Step(prefix: "command.spot.findDust", kind: .tap), Step(prefix: "command.spot.findBlemishes", kind: .tap)],
        "masking": [Step(prefix: "command.mask.add.", kind: .tap)],
        "redeye": [Step(prefix: "command.redeye.add", kind: .tap)],
        "presets": [Step(prefix: "preset.", kind: .tap), Step(prefix: "command.preset.create", kind: .tap)],
        "info": [Step(prefix: "info.allMetadata", kind: .tap), Step(prefix: "info.title", kind: .type)],
        "keywords": [Step(prefix: "keywords.entry", kind: .type)],
        "versions": [Step(prefix: "command.version.create", kind: .tap)],
        "activity": [Step(prefix: "history.", kind: .tap), Step(prefix: "command.edit.redo", kind: .tap)],
    ]

    private func tour(landscape: Bool) throws {
        startTour(name: "panels", landscape: landscape)
        defer { attachSummary() }
        for panel in Self.panelIDs {
            if let only, !only.contains(panel) { continue }
            if let limit, items.count >= limit { break }
            visit(panel)
        }
        shot("99-final")
    }

    private func visit(_ panel: String) {
        let name = "panel.\(panel)"
        ensureLoupe()
        closePanelIfOpen()
        let (button, cause) = reveal(name)
        guard let button else {
            record(name, reached: false, cause: cause, "panel button \(cause == "off-screen" ? "exists but cannot be tapped" : "not found")")
            shot("\(panel)-notreached")
            return
        }
        button.tap()
        guard element("panelTitle").waitForExistence(timeout: 6) else {
            record(name, reached: false, cause: "panel-did-not-open", "no panelTitle after tapping")
            shot("\(panel)-notopen")
            _ = alive(name)
            return
        }
        pause(1.5)
        var details: [String] = []
        let title = element("panelTitle").label
        if title.replacingOccurrences(of: "And", with: "&") != Self.panelTitles[panel] { details.append("title='\(title)' expected '\(Self.panelTitles[panel] ?? "")'") }
        shot("\(panel)-1-opened")
        if !isPad || !verticalSwitcher { expandSheet() }

        var performed = 0
        var misses: [String] = []
        var alertTexts: [String] = []
        var refusals: [String] = []
        for step in Self.steps[panel] ?? [] {
            var target = hit(prefix: step.prefix)
            var tries = 0
            while target == nil && tries < 3 && exists(prefix: step.prefix) {
                scrollPanel(); tries += 1
                target = hit(prefix: step.prefix)
            }
            guard let target else {
                misses.append("\(step.prefix)(\(exists(prefix: step.prefix) ? "off-screen" : "missing-identifier"))")
                continue
            }
            let tid = target.identifier
            switch step.kind {
            case .tap:
                target.tap()
                details.append("tap \(tid)")
            case .slide:
                let before = target.value as? String ?? ""
                let from = target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
                let to = target.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8))
                from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
                pause(1)
                let after = target.value as? String ?? ""
                details.append("slide \(tid) '\(before)' -> '\(after)'")
                if before == after { misses.append("\(tid)(no-effect: value unchanged)") }
            case .type:
                target.tap()
                target.typeText("tour\n")
                details.append("type \(tid)")
            }
            performed += 1
            pause(1.2)
            let sheet = resolveSheet()
            if !sheet.text.isEmpty { details.append(sheet.text) }
            if let r = sheet.refused { refusals.append(r) }
            alertTexts += dismissStrays()
            if !alive(name) { return }
        }
        shot("\(panel)-2-acted")
        for a in alertTexts { note("\(name): alert: \(a)") }
        for r in refusals { note("\(name): engine refused: \(r)") }
        if !alertTexts.isEmpty { details.append("ALERTS=\(alertTexts.joined(separator: " || "))") }
        if !refusals.isEmpty { details.append("REFUSED=\(refusals.joined(separator: " || "))") }
        if !misses.isEmpty { details.append("skipped: \(misses.joined(separator: ", "))") }

        // Usable state again.
        undoAll()
        closePanelIfOpen()
        if !alive(name) { return }
        if performed > 0 && !(alertTexts.count + refusals.count > 0 && false) {
            let hasNoEffect = misses.contains { $0.contains("no-effect") }
            let refused = !alertTexts.isEmpty || !refusals.isEmpty
            record(name, reached: !hasNoEffect && !refused, cause: refused ? "engine-refused" : (hasNoEffect ? "no-effect" : ""), details.joined(separator: "; "))
        } else {
            let cause = misses.contains { $0.contains("off-screen") } ? "off-screen" : "missing-identifier"
            record(name, reached: false, cause: cause, "panel opens but nothing to act on reached; " + details.joined(separator: "; "))
        }
    }
}
