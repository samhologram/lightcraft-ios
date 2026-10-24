import XCTest

/// Selects every canvas tool (`tool.<id>`), performs its gesture on the loupe, screenshots it, then
/// undoes. Only a crash fails; misses are in the `-tour-summary` attachment.
@MainActor
final class ToolTourUITests: TourTestCase {
    func testToolsPortrait() throws { try tour(landscape: false) }
    func testToolsLandscape() throws { try tour(landscape: true) }

    private func tour(landscape: Bool) throws {
        startTour(name: "tools", landscape: landscape)
        let todo = Self.toolIDs.filter { only?.contains($0) ?? true }
        for (n, tool) in todo.enumerated() {
            if let limit, items.count >= limit { break }
            if overBudget {
                recordRemaining(todo[n...].map { "tool.\($0)" } + ["tool.done"])
                shot("99-final")
                return
            }
            beginItem("tool.\(tool)")
            visit(tool)
            if Date() > itemDeadline { note("tool.\(tool): exceeded the \(Int(itemBudget)) s item budget") }
        }
        // tool.done through the palette.
        if overBudget {
            recordRemaining(["tool.done"])
        } else {
            beginItem("tool.done")
            let status = runPaletteCommand("tool.done")
            record("tool.done", reached: status == "ran", cause: status == "ran" ? "" : status, "via command palette: \(status)")
        }
        _ = dismissStrays()
        shot("99-final")
    }

    private func drag(_ target: XCUIElement, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
        if timeUp { return }
        let from = target.coordinate(withNormalizedOffset: CGVector(dx: a.0, dy: a.1))
        let to = target.coordinate(withNormalizedOffset: CGVector(dx: b.0, dy: b.1))
        from.press(forDuration: 0.15, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(0.5)
    }

    private func visit(_ tool: String) {
        let name = "tool.\(tool)"
        ensureLoupe()
        closePanelIfOpen()
        undoAll(max: 10)
        let (button, revealCause) = reveal(name)
        if let button {
            button.tap()
        } else if isPad {
            // The dock replaces the floating tool rail; tools stay available in the command palette.
            let status = runPaletteCommand(name)
            guard status == "ran" else {
                record(name, reached: false, cause: status, "tool palette command \(status)")
                shot("\(tool)-notreached")
                return
            }
        } else {
            record(name, reached: false, cause: revealCause, "tool button \(revealCause == "off-screen" ? "exists but cannot be tapped" : "not found")")
            shot("\(tool)-notreached")
            return
        }
        pause(1.5)
        var details: [String] = []
        let overlayID = tool == "guidedUpright" ? "tool.guidedUpright.overlay" : "toolOverlay.\(tool)"
        var target = element(overlayID)
        var cause = ""
        if !target.waitForExistence(timeout: 4) {
            cause = "missing-identifier"
            details.append("\(overlayID) missing; gestures sent to loupe")
            target = element("loupe")
        }
        shot("\(tool)-1-selected")
        guard target.exists else {
            record(name, reached: false, cause: "missing-identifier", "no gesture surface (loupe) on screen")
            return
        }
        switch tool {
        case "brush":
            drag(target, (0.3, 0.3), (0.7, 0.45))
            drag(target, (0.7, 0.45), (0.35, 0.55))
        case "linear": drag(target, (0.5, 0.2), (0.5, 0.6))
        case "radial": drag(target, (0.3, 0.2), (0.7, 0.6))
        case "wbPicker": target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap(); pause(0.8)
        default:
            drag(target, (0.2, 0.2), (0.25, 0.6))
            drag(target, (0.8, 0.2), (0.75, 0.6))
            drag(target, (0.2, 0.3), (0.8, 0.35))
            drag(target, (0.2, 0.55), (0.8, 0.5))
        }
        pause(1.2)
        let effect = canUndo
        details.append("gesture done; undo step registered=\(effect)")
        let alerts = dismissStrays()
        for a in alerts { note("\(name): alert: \(a)") }
        if !alerts.isEmpty { details.append("ALERTS=\(alerts.joined(separator: " || "))") }
        shot("\(tool)-2-after-gesture")
        if !alive(name) { return }
        undoAll(max: 10)
        if !effect && cause.isEmpty { cause = "no-effect" }
        record(name, reached: cause.isEmpty && alerts.isEmpty, cause: alerts.isEmpty ? cause : "engine-refused", details.joined(separator: "; "))
    }
}
