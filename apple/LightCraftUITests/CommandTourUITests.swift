import XCTest

/// Runs every command of the command palette (engine and UI commands). The id list is read from the
/// palette itself by scrolling it; each command is then found again by searching its id and run.
/// Parameter sheets are confirmed with defaults, alerts recorded in full, state restored by undo.
@MainActor
final class CommandTourUITests: TourTestCase {
    func testCommandsPortrait() throws { try tour(landscape: false) }
    func testCommandsLandscape() throws { try tour(landscape: true) }

    private struct Row { let id: String; let enabled: Bool; let label: String }

    private func enumeratePalette() -> [Row] {
        guard openPalette() else { note("enumerate: palette could not be opened"); return [] }
        expandPalette()
        shot("01-palette")
        let list = element("commandPaletteList")
        var rows: [Row] = []
        var seen = Set<String>()
        var stagnant = 0
        for _ in 0..<150 {
            if timeUp { note("enumerate: stopped by the item budget"); break }
            var fresh = 0
            for b in list.buttons.allElementsBoundByIndex where b.exists {
                let ident = b.identifier
                guard ident.hasPrefix("command."), seen.insert(ident).inserted else { continue }
                rows.append(Row(id: String(ident.dropFirst("command.".count)), enabled: b.isEnabled,
                                label: b.label.replacingOccurrences(of: "\n", with: " ")))
                fresh += 1
            }
            stagnant = fresh == 0 ? stagnant + 1 : 0
            if stagnant >= 2 { break }
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        dismissStrays()
        let att = XCTAttachment(string: rows.map { "\($0.id)\t\($0.enabled ? "enabled" : "DISABLED")\t\($0.label)" }.joined(separator: "\n"))
        att.name = "\(prefix)-palette-ids"
        att.lifetime = .keepAlways
        add(att)
        return rows
    }

    private func tour(landscape: Bool) throws {
        startTour(name: "commands", landscape: landscape)
        beginItem("enumerate")
        itemDeadline = Date().addingTimeInterval(300)
        var rows = enumeratePalette()
        extraSummaryLines.append("palette rows enumerated: \(rows.count)")
        if rows.isEmpty { XCTFail("the command palette listed no commands") ; return }
        if let only { rows = rows.filter { only.contains($0.id) } }
        if let limit { rows = Array(rows.prefix(limit)) }
        var deferred: [Row] = []
        var index = 0
        for (n, row) in rows.enumerated() {
            if overBudget {
                recordRemaining(rows[n...].map(\.id) + deferred.map(\.id))
                shot("99-final")
                return
            }
            index += 1
            beginItem(row.id)
            if !run(row, index: index, final: false) { deferred.append(row) }
        }
        // Second chance for rows that were disabled: earlier commands may have changed the state.
        for (n, row) in deferred.enumerated() {
            if overBudget {
                recordRemaining(deferred[n...].map(\.id))
                break
            }
            index += 1
            beginItem(row.id)
            _ = run(row, index: index, final: true)
        }
        shot("99-final")
    }

    /// Returns false when the row was disabled and may be retried later.
    private func run(_ row: Row, index: Int, final: Bool) -> Bool {
        let id = row.id
        let status = runPaletteCommand(id)
        var detail = ""
        var cause = ""
        var reached = false
        switch status {
        case "ran":
            reached = true
            var parts: [String] = []
            let sheet = resolveSheet()
            if !sheet.text.isEmpty { parts.append(sheet.text) }
            var refusals: [String] = []
            if let r = sheet.refused { refusals.append(r) }
            let alerts = dismissStrays()
            refusals += alerts
            if !refusals.isEmpty {
                reached = false
                cause = "engine-refused"
                parts.append("MESSAGE=" + refusals.joined(separator: " || "))
                note("\(id): \(refusals.joined(separator: " || "))")
                shot(String(format: "%03d-%@-alert", index, id))
            }
            detail = parts.joined(separator: "; ")
        case "disabled" where false: break
        default:
            if status.hasPrefix("disabled") {
                if !final { return false }
                cause = "disabled"
            } else {
                cause = status == "missing" ? "missing-identifier" : status
            }
            detail = status
        }
        if index % 10 == 0 { shot(String(format: "%03d-%@", index, id)) }
        if !alive(id) { return true }
        record(id, reached: reached, cause: cause, detail)
        recover()
        return true
    }

    /// Back to a valid document: no stray UI, undo what the command did, a photo in the loupe.
    private func recover() {
        dismissStrays()
        if !isPad || !element("palette.open").exists {
            // iPhone: undo lives in the loupe's toolbar.
            if !element("loupe").exists { openFirstPhoto() }
        } else if !element("loupe").exists {
            ensureLoupe()
        }
        undoAll(max: 4)
        if element("panelTitle").exists && !isPad { closePanelIfOpen() }
    }
}
