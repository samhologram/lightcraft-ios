import XCTest

/// Opens every panel (`panel.<id>`) through the real UI, acts on its first controls, screenshots it
/// and returns to a usable state. A crash or any NOT-REACHED panel fails the test (list in the message);
/// details are also in the `-tour-summary` attachment.
@MainActor
final class PanelTourUITests: TourTestCase {
    func testPanelsPortrait() throws { try tour(landscape: false) }
    func testPanelsLandscape() throws { try tour(landscape: true) }

    private enum Kind { case tap, slide, type }
    private struct Step { let prefix: String; let kind: Kind }

    private static let steps: [String: [Step]] = [
        // Two sliders (the 60 s item budget) plus the Auto header action.
        "edit": [Step(prefix: "control.light.exposure", kind: .slide), Step(prefix: "control.light.contrast", kind: .slide),
                 Step(prefix: "command.develop.auto", kind: .tap)],
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
        // History rows are `history.<n>`; Redo is disabled until an Undo has run, so Undo comes first.
        "activity": [Step(prefix: "history.0", kind: .tap), Step(prefix: "command.edit.undo", kind: .tap),
                     Step(prefix: "command.edit.redo", kind: .tap)],
    ]

    private func tour(landscape: Bool) throws {
        startTour(name: "panels", landscape: landscape)
        let todo = Self.panelIDs.filter { only?.contains($0) ?? true }
        for (n, panel) in todo.enumerated() {
            if let limit, items.count >= limit { break }
            if overBudget {
                recordRemaining(todo[n...].map { "panel.\($0)" })
                break
            }
            beginItem("panel.\(panel)")
            visit(panel)
            if Date() > itemDeadline { note("panel.\(panel): exceeded the \(Int(itemBudget)) s item budget") }
        }
        shot("99-final")
        let missed = items.filter { !$0.reached }
        if !missed.isEmpty {
            XCTFail("\(missed.count) of \(items.count) panels NOT-REACHED: " + missed.map { "\($0.name) [\($0.cause)]" }.joined(separator: ", "))
        }
        if items.isEmpty { XCTFail("The panel tour visited nothing") }
    }

    /// Exact-identifier lookup by element type, for controls the generic `descendants(matching: .any)` lookup can miss
    /// (`info.title` is a TextField, `info.allMetadata` a Button inside a List). Only used with exact ids.
    private func typedFallback(_ identifier: String) -> XCUIElement? {
        for e in [app.textFields[identifier], app.buttons[identifier]] where canTap(e) { return e }
        return nil
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
        let stacked = isPad && verticalSwitcher
        var details: [String] = []
        if stacked {
            // The stacked inspector: the section must exist, be expanded and be scrolled into view.
            if let cause = revealSection(panel) {
                record(name, reached: false, cause: cause, "tapped \(name) but \(cause) for panel.\(panel).section")
                shot("\(panel)-notreached")
                _ = alive(name)
                closePanelIfOpen()
                return
            }
            pause(1)
        } else {
            guard element("panelTitle").waitForExistence(timeout: 6) else {
                record(name, reached: false, cause: "panel-did-not-open", "no panelTitle after tapping")
                shot("\(panel)-notopen")
                _ = alive(name)
                return
            }
            pause(1.5)
            let title = element("panelTitle").label
            if title.replacingOccurrences(of: "And", with: "&") != Self.panelTitles[panel] { details.append("title='\(title)' expected '\(Self.panelTitles[panel] ?? "")'") }
        }
        shot("\(panel)-1-opened")
        if !isPad || !verticalSwitcher { expandSheet() }

        var performed = 0
        var misses: [String] = []
        var slideTried = 0, slideChanged = 0
        if panel == "edit" {
            // Start from the photo's defaults so repeated runs on the same catalog never accumulate (exposure hit +5.00).
            if let reset = hit("command.develop.reset") {
                reset.tap()
                pause(0.8)
                _ = dismissStrays()
                details.append("reset")
            }
        }
        var alertTexts: [String] = []
        var refusals: [String] = []
        for step in Self.steps[panel] ?? [] {
            if timeUp { misses.append("\(step.prefix)(budget)"); break }
            var target = hit(prefix: step.prefix)
            var tries = 0
            while target == nil && tries < 3 && !timeUp && exists(prefix: step.prefix) {
                scrollPanel(); tries += 1
                target = hit(prefix: step.prefix)
            }
            if target == nil, !timeUp, let t = typedFallback(step.prefix) { target = t }
            var viaMenu = false
            if target == nil, !timeUp, let t = hitInHeaderMenu(panel: panel, prefix: step.prefix) {
                target = t
                viaMenu = true
            }
            guard let target else {
                misses.append("\(step.prefix)(\(exists(prefix: step.prefix) ? "off-screen" : "missing-identifier"))")
                continue
            }
            let tid = target.identifier.isEmpty ? target.label : target.identifier
            if viaMenu { details.append("menu") }
            switch step.kind {
            case .tap:
                target.tap()
                details.append("tap \(tid)")
            case .slide:
                let before = target.value as? String ?? ""
                // Drag toward the middle of the (mostly centred) range: left when the value is positive, else right.
                let current = Double(before.replacingOccurrences(of: ",", with: ".")) ?? 0
                let toLeft = current > 0
                let from = target.coordinate(withNormalizedOffset: CGVector(dx: toLeft ? 0.6 : 0.4, dy: 0.5))
                let to = target.coordinate(withNormalizedOffset: CGVector(dx: toLeft ? 0.4 : 0.6, dy: 0.5))
                from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)
                pause(0.5)
                let after = target.value as? String ?? ""
                details.append("slide \(tid) '\(before)' -> '\(after)'")
                slideTried += 1
                if before != after { slideChanged += 1 }
            case .type:
                target.tap()
                // "\n" makes XCUITest tap the on-screen Return key, which is not always hittable (it failed
                // the tour); commit only when it is, else end editing by tapping a neutral spot.
                target.typeText("tour")
                let enter = ["Return", "return", "Done", "done"].map { app.keyboards.buttons[$0].firstMatch }
                    .first { $0.exists && $0.isHittable }
                if let enter {
                    enter.tap()
                } else if app.keyboards.count > 0 {
                    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
                }
                details.append("type \(tid)")
            }
            performed += 1
            pause(panel == "edit" ? 0.5 : 1.2)
            let sheet = resolveSheet()
            if !sheet.text.isEmpty { details.append(sheet.text) }
            if let r = sheet.refused { refusals.append(r) }
            alertTexts += dismissStrays()
            if !alive(name) { return }
        }
        if slideTried > 0 && slideChanged == 0 { misses.append("sliders(no-effect: no slider value changed)") }
        shot("\(panel)-2-acted")
        for a in alertTexts { note("\(name): alert: \(a)") }
        for r in refusals { note("\(name): engine refused: \(r)") }
        if !alertTexts.isEmpty { details.append("ALERTS=\(alertTexts.joined(separator: " || "))") }
        if !refusals.isEmpty { details.append("REFUSED=\(refusals.joined(separator: " || "))") }
        if !misses.isEmpty { details.append("skipped: \(misses.joined(separator: ", "))") }

        // Usable state again.
        if stacked { collapseSection(panel) }
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
