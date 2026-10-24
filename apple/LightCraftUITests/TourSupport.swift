import XCTest
import UIKit

/// One visited item of a coverage tour.
struct TourItem {
    let name: String
    let reached: Bool
    /// Cause class of a miss: off-screen, missing-identifier, engine-refused, no-effect, disabled, ...
    let cause: String
    let detail: String
}

/// Shared driver of the coverage tours (panels, tools, commands). Every item is visited through the
/// real UI; only a crash fails a test. Everything else is recorded in the `-tour-summary` attachment,
/// where a miss ("NOT-REACHED") stays visible as a bug to fix, never as a pass.
///
/// Environment (pass as `TEST_RUNNER_<NAME>=...` to xcodebuild): `TOUR_LIMIT=n` visits only the first
/// n items, `TOUR_ONLY=a,b` only those ids (panel/tool/command ids without the `command.` prefix).
@MainActor
class TourTestCase: LightCraftUITestCase {
    var items: [TourItem] = []
    var landscape = false
    var tourName = ""
    var summaryAttached = false
    var extraSummaryLines: [String] = []
    var crashed = false

    // MARK: Time budget (hang-proofing)

    /// Whole-test budget in seconds (`TOUR_BUDGET`, default 840 so a 900 s external timeout still sees the summary).
    var budget: TimeInterval { ProcessInfo.processInfo.environment["TOUR_BUDGET"].flatMap { TimeInterval($0) } ?? 840 }
    /// Longest an item may take.
    let itemBudget: TimeInterval = 60
    /// Longest any single element wait may take.
    let waitCap: TimeInterval = 20
    var tourStart = Date()
    var itemDeadline = Date.distantFuture
    var currentItem = "start"

    var overBudget: Bool { Date().timeIntervalSince(tourStart) > budget }
    /// True when the whole budget or the current item's 60 s is spent: loops must stop and record.
    var timeUp: Bool { overBudget || Date() > itemDeadline }

    func beginItem(_ name: String) {
        currentItem = name
        itemDeadline = Date().addingTimeInterval(itemBudget)
        print("TOUR \(name) begin")
    }

    /// Records every id not yet visited as "not reached (budget)".
    func recordRemaining(_ ids: [String]) {
        for id in ids { record(id, reached: false, cause: "budget", "not reached (budget)") }
    }

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 900
        tourStart = Date()
        // A leftover process of the previous test blocks the next launch (XCUITest hangs in "Terminate").
        XCUIApplication().terminate()
    }

    override func tearDown() {
        attachSummary()
        flushNotes()
        app?.terminate()
        super.tearDown()
    }

    override func note(_ text: String) {
        super.note(text)
        appendHost("/tmp/lctour-\(prefix)-notes.log", text + "\n")
    }

    func appendHost(_ path: String, _ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { FileManager.default.createFile(atPath: path, contents: data) }
    }

    static let panelIDs = ["edit", "profiles", "crop", "remove", "masking", "redeye", "presets", "info",
                           "keywords", "versions", "activity"]
    static let toolIDs = ["brush", "linear", "radial", "wbPicker", "guidedUpright"]
    static let panelTitles = ["edit": "Edit", "profiles": "Profiles", "crop": "Crop & Rotate", "remove": "Remove",
                              "masking": "Masking", "redeye": "Red Eye", "presets": "Presets", "info": "Info",
                              "keywords": "Keywords", "versions": "Versions", "activity": "History"]

    var limit: Int? { ProcessInfo.processInfo.environment["TOUR_LIMIT"].flatMap { Int($0) } }
    var only: Set<String>? {
        guard let v = ProcessInfo.processInfo.environment["TOUR_ONLY"], !v.isEmpty else { return nil }
        return Set(v.split(separator: ",").map { String($0) })
    }

    // MARK: Setup

    /// Launches the demo app in the given orientation, creates a library and opens the first photo.
    func startTour(name: String, landscape: Bool) {
        self.landscape = landscape
        tourName = name
        tourStart = Date()
        beginItem("start")
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        launchDemo(dark: false)
        continueAfterFailure = true
        prefix = "\(isPad ? "ipad" : "iphone")-\(landscape ? "landscape" : "portrait")-\(name)"
        print("TOUR start launched")
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(2)
        openLibraryBounded()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(1)
        shot("00-library")
        if !openFirstPhoto() { note("start: could not open the first photo") }
        pause(2)
    }

    /// `openNewDemoLibrary` with bounded waits and a plain identifier lookup for `demoReady` (no NSPredicate).
    func openLibraryBounded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
            let button = springboard.alerts.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        let ready = app.descendants(matching: .any)["demoReady"].firstMatch
        var attempts = 0
        while attempts < 3 && !overBudget {
            attempts += 1
            if ready.waitForExistence(timeout: waitCap) { pause(3); return }
            print("TOUR start demoReady not yet (\(attempts)/3)")
        }
        XCTFail("The Photos grid never became ready (\(Int(waitCap) * attempts) s)")
        note("demoReady never appeared")
    }

    // MARK: Recording

    func record(_ name: String, reached: Bool, cause: String = "", _ detail: String = "") {
        items.append(TourItem(name: name, reached: reached, cause: cause, detail: detail))
        let line = "\(reached ? "REACHED" : "NOT-REACHED") \(name) [\(cause)] \(detail)"
        NSLog("TOUR %@", line)
        print("TOUR \(name) \(reached ? "REACHED" : "NOT-REACHED") [\(cause)]")
        let att = XCTAttachment(string: line)
        att.name = "\(prefix)-item-\(name)"
        att.lifetime = .keepAlways
        add(att)
        // Mirror on the host: a crash or an external kill can end the run before any attachment exists.
        appendHost("/tmp/lctour-\(prefix).log", line + "\n")
        writeSummaryFile()
    }

    func summaryLines() -> [String] {
        let reached = items.filter(\.reached).count
        let missed = items.filter { !$0.reached }
        var causes: [String: Int] = [:]
        for m in missed { causes[m.cause, default: 0] += 1 }
        var lines = ["\(prefix) tour summary",
                     "items: \(items.count)  reached: \(reached)  not-reached: \(missed.count)",
                     "not-reached by cause: " + (causes.isEmpty ? "none" : causes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")),
                     "elapsed: \(Int(Date().timeIntervalSince(tourStart))) s of budget \(Int(budget)) s; last item: \(currentItem)",
                     ""]
        if !crashItems.isEmpty { lines += ["CRASHES at: " + crashItems.joined(separator: ", "), ""] }
        lines += items.map { i in
            i.reached ? "REACHED      \(i.name)  \(i.detail)" : "NOT-REACHED  \(i.name)  [\(i.cause)] \(i.detail)"
        }
        if !extraSummaryLines.isEmpty { lines += ["", "extra:"] + extraSummaryLines }
        lines += ["", "notes:"] + (notes.isEmpty ? ["none"] : notes)
        return lines
    }

    func writeSummaryFile() {
        try? summaryLines().joined(separator: "\n").write(toFile: "/tmp/lctour-\(prefix)-summary.txt", atomically: true, encoding: .utf8)
    }

    func attachSummary() {
        guard !summaryAttached else { return }
        summaryAttached = true
        writeSummaryFile()
        let attachment = XCTAttachment(string: summaryLines().joined(separator: "\n"))
        attachment.name = "\(prefix)-tour-summary"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    var crashItems: [String] = []
    var relaunches: [String] = []

    /// True while the app runs in the foreground. After a crash the item is recorded as CRASH, the
    /// test is failed (the tour goes on so later items are still covered), and the app is relaunched
    /// on a fresh demo library; returns false.
    func alive(_ item: String) -> Bool {
        if app.state == .runningForeground && app.windows.firstMatch.exists { return true }
        crashed = true
        crashItems.append(item)
        record(item, reached: false, cause: "CRASH", "app state \(app.state.rawValue) after this item; relaunched")
        XCTFail("CRASH (app not running in the foreground) at \(item)")
        relaunch()
        return false
    }

    /// Fresh launch on a new demo library (after a crash, or when the UI is stuck beyond recovery).
    func relaunch() {
        let saved = prefix
        app.terminate()
        launchDemo(dark: false)
        continueAfterFailure = true
        prefix = saved
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(2)
        openLibraryBounded()
        pause(1)
        openFirstPhoto()
        pause(2)
    }

    // MARK: Element lookup

    /// On screen and tappable. The frame is checked first: `isHittable` itself fails the test for
    /// elements scrolled far out of view.
    func canTap(_ candidate: XCUIElement) -> Bool {
        // firstMatch: a query that matches several elements throws "Multiple matching elements found" on frame access.
        let e = candidate.firstMatch
        guard e.exists else { return false }
        let f = e.frame
        let w = app.windows.firstMatch.frame
        guard !f.isEmpty, w.contains(CGPoint(x: f.midX, y: f.midY)) else { return false }
        return e.isHittable
    }

    /// The first element with `identifier` that can be tapped.
    func hit(_ identifier: String) -> XCUIElement? {
        let q = app.descendants(matching: .any).matching(identifier: identifier)
        for e in q.allElementsBoundByIndex where canTap(e) { return e }
        return nil
    }

    /// Identifiers starting with `prefix`, in tree order, from ONE accessibility snapshot. No NSPredicate
    /// (its evaluation is blocked in the runner: "_evaluationBlocked" faults) and no per-element IPC.
    func ids(prefix: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [String] = []
        var seen = Set<String>()
        func walk(_ node: XCUIElementSnapshot) {
            let id = node.identifier
            // Full-screen and Guided Upright controls change the layout, not a setting: never tour them.
            let layout = id.hasPrefix("control.fullscreen") || id.hasPrefix("control.guidedUpright")
            // Tap-to-type value labels (`control.x.value`, `.value.done`) are not sliders.
            let valueLabel = id.hasSuffix(".value") || id.hasSuffix(".value.done")
            if id.hasPrefix(prefix), !layout, !valueLabel, seen.insert(id).inserted { found.append(id) }
            for child in node.children { walk(child) }
        }
        walk(root)
        return found
    }

    func hit(prefix: String) -> XCUIElement? {
        for id in ids(prefix: prefix) {
            if let e = hit(id) { return e }
        }
        return nil
    }

    func exists(prefix: String) -> Bool { !ids(prefix: prefix).isEmpty }

    /// Grid cells `photo.<digits>` (not `photo.on.rectangle` and other symbol names), in numeric order.
    func photoCellIDs() -> [String] {
        let cells = ids(prefix: "photo.").compactMap { id -> (Int, String)? in
            let suffix = id.dropFirst("photo.".count)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0 >= "0" && $0 <= "9" }), let n = Int(suffix) else { return nil }
            return (n, id)
        }
        return cells.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// First tappable grid cell, `photo.0` first.
    func hitPhotoCell() -> XCUIElement? {
        for id in photoCellIDs() { if let e = hit(id) { return e } }
        return nil
    }

    /// For an item living in a header menu (`panel.<id>.find` / `.add` / `.menu`): opens each such menu in turn
    /// and returns the first tappable element with `prefix`. The menu is left open (tapping the item closes it);
    /// when nothing matches, the menu is dismissed and nil returned.
    /// Menu item labels (SwiftUI `Menu` items on iPad expose no identifier): command id prefix -> labels.
    static let menuLabels: [String: [String]] = [
        "command.mask.add.": ["Subject", "Sky", "Background"],
        "command.spot.findDust": ["Find Dust Spots"],
        "command.spot.findBlemishes": ["Find Blemishes"],
        "view.maskOverlay": ["Show Overlay"],
        "tool.brush": ["Brush"], "tool.linear": ["Linear Gradient"], "tool.radial": ["Radial Gradient"],
    ]

    /// A tappable menu item found by identifier, else by label (`menuLabels`).
    func hitMenuItem(prefix: String) -> XCUIElement? {
        if let e = hit(prefix: prefix) { return e }
        for label in Self.menuLabels[prefix] ?? [] {
            for q in [app.buttons[label], app.menuItems[label]] {
                let e = q.firstMatch
                if e.exists, canTap(e) { return e }
            }
        }
        return nil
    }

    /// For an item living in a header menu (`panel.<id>.find` / `.add` / `.menu`): opens each such menu in turn
    /// and returns the first tappable element with `prefix` (by identifier, falling back to the menu label). The menu
    /// is left open (tapping the item closes it); when nothing matches, the menu is dismissed and nil returned.
    func hitInHeaderMenu(panel: String, prefix: String) -> XCUIElement? {
        for suffix in ["find", "add", "menu"] {
            let id = "panel.\(panel).\(suffix)"
            guard let opener = hit(id) else { continue }
            opener.tap()
            pause(0.8)
            if let e = hitMenuItem(prefix: prefix) { return e }
            if app.keyboards.count == 0 { dismissOpenSelector() }
            pause(0.5)
        }
        return nil
    }

    /// Dismiss an open native menu or anchored popover through actual content, away from the status bar.
    /// The loupe occupies the canvas side of the editor, outside inspector header selectors.
    func dismissOpenSelector() {
        let region = app.otherElements["PopoverDismissRegion"].firstMatch
        if region.exists && region.isHittable {
            region.tap()
        } else {
            let canvas = element("loupe")
            if canvas.exists && !canvas.frame.isEmpty {
                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            } else {
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)).tap()
            }
        }
    }

    /// True when the iPad's persistent tab dock is present (otherwise the iPhone's strip/sheet).
    var verticalSwitcher: Bool { element("inspector").exists }

    /// A `panel.<id>` / `tool.<id>` button that can be tapped, scrolling the switcher when needed.
    /// The second value is the cause class when it cannot be reached.
    func reveal(_ identifier: String) -> (XCUIElement?, String) {
        if identifier.hasPrefix("panel."), verticalSwitcher {
            let panel = String(identifier.dropFirst("panel.".count))
            if let tab = hit("panelTab.\(panel)") { return (tab, "") }
            if let add = hit("control.panelMenu") {
                add.tap()
                pause(0.5)
                if let item = hit("control.panelMenu.\(panel)") { return (item, "") }
                if let title = Self.panelTitles[panel] {
                    let item = app.buttons[title].firstMatch
                    if canTap(item) { return (item, "") }
                }
            }
            return (nil, "panel-tab-or-add-menu-missing")
        }
        if let e = hit(identifier) { return (e, "") }
        guard element(identifier).exists else { return (nil, "missing-identifier") }
        let order = Self.panelIDs.map { "panel.\($0)" } + Self.toolIDs.map { "tool.\($0)" }
        guard let index = order.firstIndex(of: identifier) else { return (nil, "off-screen") }
        let vertical = verticalSwitcher
        for _ in 0..<8 {
            if timeUp { return (nil, "off-screen") }
            // The nearest visible sibling is the scrolling handle.
            var anchor: (XCUIElement, Int)?
            for offset in 1..<order.count {
                for candidate in [index - offset, index + offset] where order.indices.contains(candidate) {
                    if let e = hit(order[candidate]) { anchor = (e, candidate); break }
                }
                if anchor != nil { break }
            }
            guard let (handle, handleIndex) = anchor else { return (nil, "off-screen") }
            let forward = index > handleIndex
            if vertical {
                if forward { handle.swipeUp(velocity: .slow) } else { handle.swipeDown(velocity: .slow) }
            } else {
                if forward { handle.swipeLeft(velocity: .slow) } else { handle.swipeRight(velocity: .slow) }
            }
            pause(0.5)
            if let e = hit(identifier) { return (e, "") }
        }
        return (nil, "off-screen")
    }

    // MARK: Photo and panels

    /// Identifiers the editor exposes once a photo is open. On iPad the loupe container can be missing from the
    /// accessibility tree (it is a `.contain` element under a customizable toolbar), so the other things that only
    /// exist in the editor count too: the loupe toolbar items, the inspector column, the panel switcher, `mode.grid`
    /// (the Library button, shown only while a photo is open), the Full Screen button, the Exposure slider.
    static let loupeSignals = ["loupe", "inspector", "toolbar.beforeAfter", "toolbar.zoom", "mode.grid",
                               "control.fullscreen", "control.light.exposure", "panelTitle"]

    /// The first loupe signal on screen, or nil. A plain existence check.
    func loupeSignal() -> String? {
        for id in Self.loupeSignals where element(id).exists { return id }
        return nil
    }

    /// Waits up to `timeout` s (default and cap 30 s) for any loupe signal; records which one it found.
    func waitForLoupe(timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(min(timeout, 30))
        repeat {
            if let id = loupeSignal() {
                note("loupe open, found '\(id)'")
                return true
            }
            pause(0.5)
        } while Date() < deadline
        return false
    }

    @discardableResult
    func openFirstPhoto() -> Bool {
        if loupeSignal() != nil { return true }
        let deadline = Date().addingTimeInterval(waitCap)
        while Date() < deadline && !overBudget {
            if let cell = hitPhotoCell() {
                cell.tap()
                // The photo opens asynchronously ("Opening…" overlay); a tap that landed before the grid was
                // interactive is repeated once the overlay is gone and the grid is still there.
                if waitForLoupe(timeout: 20) { return true }
                if element("photos.opening").exists || !waitForLoupe(timeout: 10) {
                    let present = Array(Self.loupeSignals.filter { element($0).exists })
                    note("openFirstPhoto: no loupe signal after tapping \(cell.identifier); present: \(present)")
                }
                if loupeSignal() != nil { return true }
                continue
            }
            pause(1)
        }
        return loupeSignal() != nil
    }

    /// Back to the loupe when something left it.
    func ensureLoupe() {
        if loupeSignal() != nil, !element("photos.opening").exists, hit("mode.loupe") == nil { return }
        if let b = hit("mode.loupe") { b.tap(); pause(1.5) }
        if loupeSignal() == nil { openFirstPhoto() }
        pause(1)
    }

    func closePanelIfOpen() {
        guard element("panelTitle").exists else { return }
        if hit("panel.close") == nil { pause(1) }
        if let close = hit("panel.close") {
            close.tap()
            let deadline = Date().addingTimeInterval(5)
            while element("panelTitle").exists && Date() < deadline { pause(0.4) }
            pause(0.8)
        } else {
            note("panel.close not hittable while a panel is open")
            // Fallback: the inspector's own top-trailing corner, where the close button sits.
            let inspector = element("inspector")
            if inspector.exists {
                inspector.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 26)).tap()
                pause(1)
            }
        }
    }

    /// Phone: pull the panel sheet up from its detent so the controls fit.
    func expandSheet() {
        guard !verticalSwitcher, element("panelTitle").exists else { return }
        let title = element("panelTitle")
        let from = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: -320))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(1)
    }

    /// Scrolls the open panel's content up. iPad: drags the inspector column along its left padding strip (no
    /// control there, so no slider is nudged); iPhone: drags inside the sheet below its title.
    func scrollPanel() {
        let inspector = element("inspector")
        if inspector.exists {
            let from = inspector.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            let to = inspector.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(0.6)
            return
        }
        let title = element("panelTitle")
        guard title.exists else { return }
        let from = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 330))
        let to = from.withOffset(CGVector(dx: 0, dy: -240))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(0.6)
    }

    /// iPad stacked inspector: waits for `panel.<id>.section`, then scrolls the inspector (up to `maxScrolls`,
    /// down as well when it overshot) until the section's header or collapse button can be tapped. Expands a
    /// collapsed section. Returns a failure cause, or nil when the section is on screen and expanded.
    func revealSection(_ panel: String, maxScrolls: Int = 8) -> String? {
        let section = element("panel.\(panel).section")
        guard section.waitForExistence(timeout: 8) else { return "section-missing" }
        let candidates = ["panel.\(panel).collapse", "panel.\(panel).header", "panel.\(panel).section"]
        func visible() -> XCUIElement? { for id in candidates { if let e = hit(id) { return e } }; return nil }
        var tries = 0
        while visible() == nil && tries < maxScrolls && !timeUp {
            let inspector = element("inspector")
            if inspector.exists { if tries < maxScrolls / 2 + 1 { inspector.swipeUp(velocity: .slow) } else { inspector.swipeDown(velocity: .slow) } }
            pause(0.5)
            tries += 1
        }
        guard visible() != nil else { return "off-screen" }
        let collapse = element("panel.\(panel).collapse")
        if collapse.exists, (collapse.value as? String) == "Collapsed", let c = hit(collapse.identifier) {
            c.tap()
            pause(0.8)
        }
        return nil
    }

    /// Collapses a stacked section again (not Edit, which is the default-open one) so later panels get room.
    func collapseSection(_ panel: String) {
        guard panel != "edit" else { return }
        let collapse = element("panel.\(panel).collapse")
        if collapse.exists, (collapse.value as? String) == "Expanded", let c = hit(collapse.identifier) { c.tap(); pause(0.5) }
    }

    // MARK: Undo

    var canUndo: Bool {
        let u = element("command.edit.undo")
        return u.exists && u.isEnabled
    }

    func undoAll(max count: Int = 6) {
        for _ in 0..<count {
            if overBudget { return }
            let u = element("command.edit.undo")
            guard u.exists, u.isEnabled, canTap(u) else { return }
            u.tap()
            pause(0.6)
        }
    }

    // MARK: Alerts, sheets, strays

    /// Dismisses what the last action left open (alert, parameter sheet, dialogs, share sheets) and
    /// returns the full text of every alert met on the way.
    @discardableResult
    func dismissStrays(label: String = "") -> [String] {
        var alerts: [String] = []
        for _ in 0..<5 {
            if app.alerts.firstMatch.exists, let text = dismissAlert() {
                alerts.append(text)
                pause(0.6)
                continue
            }
            var acted = false
            for id in ["command.sheet.cancel", "export.done", "palette.done"] where element(id).exists {
                if let c = hit(id) { c.tap(); pause(0.8); acted = true; break }
            }
            if acted { continue }
            if app.sheets.firstMatch.exists {
                let dialogCancel = app.sheets.buttons["Cancel"].firstMatch
                if dialogCancel.exists && dialogCancel.isHittable { dialogCancel.tap(); pause(0.8); continue }
            }
            if app.popovers.firstMatch.exists {
                let popCancel = app.popovers.buttons["Cancel"].firstMatch
                if popCancel.exists && popCancel.isHittable { popCancel.tap(); pause(0.8); continue }
            }
            for title in ["Cancel", "Done"] {
                let b = app.buttons[title].firstMatch
                if b.exists, b.isHittable, !element("loupe").isHittable || title == "Cancel" {
                    if app.sheets.firstMatch.exists || app.popovers.firstMatch.exists || app.otherElements["PopoverDismissRegion"].exists || app.navigationBars.count > 1 {
                        b.tap(); pause(0.8); acted = true; break
                    }
                }
            }
            if acted { continue }
            if app.otherElements["ActivityListView"].exists {
                let close = app.buttons["Close"].firstMatch
                if close.exists, close.isHittable { close.tap(); pause(0.8); continue }
            }
            break
        }
        return alerts
    }

    /// If a parameter sheet is open: fill defaults, confirm, record the engine's message (error or
    /// query result), close it. Returns a description ("" when no sheet).
    func resolveSheet() -> (text: String, refused: String?) {
        let run = element("command.sheet.run")
        guard run.waitForExistence(timeout: 2) else { return ("", nil) }
        var text = "sheet"
        if run.exists && !run.isEnabled {
            // Required text fields without defaults: type a plain value.
            for field in app.textFields.allElementsBoundByIndex where field.exists && field.isHittable {
                let value = (field.value as? String) ?? ""
                if value.isEmpty || value == field.placeholderValue {
                    field.tap()
                    field.typeText("Tour")
                    text += " filled-text"
                }
            }
            // Never tap keyboard keys: XCUITest reports Return as hittable yet fails to scroll it into view
            // (kAXErrorFailure). The sheet's Run button works with the keyboard up.
            pause(0.4)
        }
        var refused: String?
        if run.exists && run.isEnabled && run.isHittable {
            run.tap()
            text += " run"
            pause(1.5)
            let err = element("command.sheet.error")
            if err.exists {
                refused = err.label
                text += " ERROR"
            }
            let result = element("command.sheet.result")
            if result.exists { text += " result=\(String(result.label.prefix(120)).replacingOccurrences(of: "\n", with: " "))" }
        } else if run.exists {
            text += " apply-disabled"
            refused = "parameter sheet Apply stays disabled with defaults"
        }
        if element("command.sheet.cancel").exists { _ = hit("command.sheet.cancel").map { $0.tap() } }
        pause(0.8)
        return (text, refused)
    }

    // MARK: Command palette

    /// Opens the palette: the toolbar button on iPad, the grid's More menu on iPhone (the loupe's
    /// toolbar has no palette entry there).
    func openPalette() -> Bool {
        dismissStrays()
        if let b = hit("palette.open") {
            b.tap()
        } else {
            if element("loupe").exists, let back = hit("mode.grid") { back.tap(); pause(1.5) }
            guard let more = hit("menu.more") else { note("palette: no palette.open and no menu.more"); return false }
            more.tap()
            pause(0.8)
            guard let p = hit("palette.open") else {
                note("palette: palette.open missing from the More menu")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
                pause(0.6)
                return false
            }
            p.tap()
        }
        return element("commandPaletteList").waitForExistence(timeout: 8)
    }

    func expandPalette() {
        let nav = app.navigationBars["Command Palette"].firstMatch
        guard nav.exists else { return }
        let from = nav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: -400))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(0.8)
    }

    /// Runs one palette command by searching for its id. Returns a status: "ran", "disabled: <label>"
    /// or "missing".
    func runPaletteCommand(_ id: String) -> String {
        if !openPalette() {
            dismissStrays()
            pause(1)
            if !openPalette() {
                note("\(id): palette unreachable; relaunching the app on a fresh library")
                relaunches.append("\(id) (app state \(app.state.rawValue))")
                extraSummaryLines.append("RELAUNCH before \(id): the palette could not be opened (app state \(app.state.rawValue))")
                relaunch()
                guard openPalette() else { return "palette-unreachable" }
            }
        }
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText(id)
            pause(0.6)
            let key = app.keyboards.buttons["Search"].firstMatch
            if key.exists && key.isHittable { key.tap() }
            pause(0.4)
        }
        var row: XCUIElement?
        for attempt in 0..<4 {
            if timeUp { break }
            let q = app.buttons.matching(identifier: "command.\(id)")
            for e in q.allElementsBoundByIndex where canTap(e) { row = e; break }
            if row != nil { break }
            if attempt < 3, element("commandPaletteList").exists {
                let list = element("commandPaletteList")
                let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
                pause(0.4)
            }
        }
        guard let row else {
            dismissStrays()
            return app.buttons.matching(identifier: "command.\(id)").firstMatch.exists ? "off-screen" : "missing"
        }
        if !row.isEnabled {
            let label = row.label.replacingOccurrences(of: "\n", with: " ")
            dismissStrays()
            return "disabled: \(label)"
        }
        row.tap()
        pause(1.8)
        return "ran"
    }
}
