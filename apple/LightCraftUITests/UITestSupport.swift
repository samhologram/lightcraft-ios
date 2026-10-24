import XCTest
import UIKit

/// Shared driver for the UI tests: launches with `-LightCraftDemo`, creates a library from the launch
/// scene, waits for the demo photos, takes screenshots and records missing elements as notes (a
/// `-notes` attachment) instead of failing. Only a missing window or library fails a test.
@MainActor
class LightCraftUITestCase: XCTestCase {
    var app: XCUIApplication!
    var notes: [String] = []
    var prefix = ""
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func launchDemo(dark: Bool, extraArguments: [String] = []) {
        launch(args: ["-LightCraftDemo"] + extraArguments, prefix: "\(isPad ? "ipad" : "iphone")-\(dark ? "dark" : "light")", dark: dark)
    }

    /// Launches WITHOUT `-LightCraftDemo`, so the app shows its real permission states (denied / limited
    /// UI) instead of falling back to the engine's sample photos.
    func launchPlain(extraArguments: [String] = []) {
        launch(args: extraArguments, prefix: "\(isPad ? "ipad" : "iphone")-plain", dark: false)
    }

    private func launch(args: [String], prefix: String, dark: Bool) {
        continueAfterFailure = false
        self.prefix = prefix
        notes = []
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // A loaded machine can take minutes to bring the app up, and the accessibility server can be missing
        // right after launch (kAXErrorServerNotFound), so wait long and relaunch once before failing.
        for attempt in 1...2 {
            app.launch()
            let foreground = app.wait(for: .runningForeground, timeout: 300)
            if foreground && app.descendants(matching: .any)["demoReady"].waitForExistence(timeout: 1) { return }
            if foreground && app.windows.firstMatch.waitForExistence(timeout: 180) { return }
            let state = app.state.rawValue
            print("LAUNCH attempt \(attempt) failed: foreground=\(foreground) state=\(state)")
            notes.append("launch attempt \(attempt): foreground=\(foreground), state=\(state), no window")
            app.terminate()
        }
        XCTFail("The app did not launch with a window after 2 attempts (see notes)")
    }

    /// The Photos state the runner set up (`LC_EXPECT_PHOTOS`, forwarded by `TEST_RUNNER_LC_EXPECT_PHOTOS`);
    /// nil when the test runs outside the runner.
    var expectedPhotosState: String? {
        let v = ProcessInfo.processInfo.environment["LC_EXPECT_PHOTOS"] ?? ""
        return v.isEmpty ? nil : v
    }

    /// A state test could not reach its precondition: fails when the runner set an expectation (a skip would
    /// count as a pass), skips only when none was set. Callers `return` after it when it did not throw.
    func skipOrFail(_ message: String) throws {
        if let expected = expectedPhotosState {
            XCTFail("\(message) (runner expected Photos state: \(expected))")
        } else {
            throw XCTSkip(message)
        }
    }

    /// The Edit panel on iPhone is open by default and its strip toggles, so tap it only when the exposure
    /// slider is not already there. On iPad the panel is always visible.
    func ensureEditPanelOpen() {
        guard !isPad, !element("control.light.exposure").waitForExistence(timeout: 3) else { return }
        tap("panel.edit")
    }

    /// Polls until the element with `identifier` no longer exists; returns whether it went away.
    @discardableResult
    func waitForGone(_ identifier: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element(identifier).exists { return true }
            pause(1)
        }
        return !element(identifier).exists
    }

    /// Waits until any of the identifiers exists; returns the first found (nil on timeout).
    func waitForAny(_ identifiers: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for id in identifiers where element(id).exists { return id }
            pause(1)
        }
        return nil
    }

    /// Waits for the Photos grid (the app opens straight onto the Photos library; there is no document to
    /// create any more). Allows a Photos permission prompt if one shows. On return the grid is showing and
    /// `demoReady` exists.
    func openNewDemoLibrary() {
        pause(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
            let button = springboard.alerts.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                break
            }
        }
        XCTAssertTrue(element("demoReady").waitForExistence(timeout: 180), "The Photos grid never became ready")
        pause(3)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Taps the element with `identifier` if it can be reached; records a note otherwise.
    @discardableResult
    func tap(_ identifier: String, timeout: TimeInterval = 5) -> Bool {
        let e = element(identifier)
        guard e.waitForExistence(timeout: timeout) else { note("\(identifier): not found"); return false }
        guard e.isHittable else { note("\(identifier): exists but not hittable (off screen or covered)"); return false }
        e.tap()
        return true
    }

    /// The full message of an alert on screen, dismissed; nil when none.
    func dismissAlert() -> String? {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return nil }
        let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " | ")
        let button = alert.buttons.firstMatch
        if button.exists { button.tap() }
        return text
    }

    func pause(_ seconds: TimeInterval) {
        let e = expectation(description: "pause")
        e.isInverted = true
        wait(for: [e], timeout: seconds)
    }

    func shot(_ suffix: String) {
        // `--no-screenshots` on the runner sets LC_NO_SCREENSHOTS (notes and summaries are still attached).
        if let v = ProcessInfo.processInfo.environment["LC_NO_SCREENSHOTS"], !v.isEmpty, v != "0" { return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(prefix)-\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func note(_ text: String) {
        notes.append(text)
        NSLog("LightCraftUITests note: %@", text)
    }

    func flushNotes(_ name: String = "notes") {
        let attachment = XCTAttachment(string: notes.isEmpty ? "no notes" : notes.joined(separator: "\n"))
        attachment.name = "\(prefix)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - User-story helpers (UserStoryUITests)

/// Per-story record: interaction count, every checked step (label, passed) and the UX audit findings.
@MainActor
final class StoryRecorder {
    var taps = 0
    var steps: [(String, Bool)] = []
    var uxIssues: [String] = []
}

/// Appends one line to the shared story summary file (`/tmp/lcstory-summary.txt`, as the orchestrator expects).
private func appendStorySummaryLine(_ line: String) {
    let path = "/tmp/lcstory-summary.txt"
    let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

@MainActor
extension LightCraftUITestCase {
    /// Taps `id` when it appears within 5 s and becomes hittable within about 2 s. Records the step.
    @discardableResult
    func storyTap(_ id: String, _ r: StoryRecorder) -> Bool {
        let e = element(id)
        guard e.waitForExistence(timeout: 5) else {
            r.steps.append((id, false))
            return false
        }
        var hittable = e.isHittable
        var tries = 0
        while !hittable && tries < 10 {
            pause(0.2)
            hittable = e.isHittable
            tries += 1
        }
        guard hittable else {
            r.steps.append(("\(id) (not hittable)", false))
            return false
        }
        e.tap()
        r.taps += 1
        r.steps.append((id, true))
        return true
    }

    /// Long-presses `id` (opens a grid cell's context menu). Records the step.
    @discardableResult
    func storyPress(_ id: String, _ r: StoryRecorder) -> Bool {
        let e = element(id)
        guard e.waitForExistence(timeout: 5) else {
            r.steps.append(("\(id) (long-press)", false))
            return false
        }
        e.press(forDuration: 1.2)
        r.taps += 1
        r.steps.append(("\(id) (long-press)", true))
        return true
    }

    /// Taps a menu item or button found by its visible label (menus often expose no identifier).
    @discardableResult
    func storyTapLabel(_ label: String, _ r: StoryRecorder) -> Bool {
        for q in [app.menuItems[label], app.buttons[label]] {
            let e = q.firstMatch
            if e.waitForExistence(timeout: 3) && e.isHittable {
                e.tap()
                r.taps += 1
                r.steps.append(("label:\(label)", true))
                return true
            }
        }
        r.steps.append(("label:\(label)", false))
        return false
    }

    /// Records a checked condition as a step. Does not fail the test by itself; `storyAssertAll` does.
    @discardableResult
    func storyCheck(_ ok: Bool, _ label: String, _ r: StoryRecorder) -> Bool {
        r.steps.append((label, ok))
        return ok
    }

    /// Fails the test once, naming every step that was missed or failed.
    func storyAssertAll(_ story: String, _ r: StoryRecorder) {
        let missed = r.steps.filter { !$0.1 }.map { $0.0 }
        XCTAssertTrue(missed.isEmpty, "\(story): \(missed.count) step(s) missed or failed: \(missed.joined(separator: ", "))")
    }

    /// The accessibility value of `id` as a string ("" when none).
    func storyValue(_ id: String) -> String {
        (element(id).value as? String) ?? ""
    }

    /// The numeric part of a slider value such as "+1.00" or "1 EV"; nil when there is none.
    func storyNumber(_ text: String) -> Double? {
        Double(String(text.filter { "0123456789.-".contains($0) }))
    }

    /// Sets an exact value through the slider's tap-to-type field (`<control>.value`): tap, clear, type, then
    /// tap `<control>.value.done` when it shows, else tap near the top edge of the window.
    @discardableResult
    func storyEnterValue(_ control: String, _ text: String, _ r: StoryRecorder) -> Bool {
        let field = "\(control).value"
        guard storyTap(field, r) else { return false }
        app.typeText(String(repeating: "\u{8}", count: 8) + text)
        pause(0.3)
        let done = "\(field).done"
        if element(done).exists {
            storyTap(done, r)
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        }
        pause(0.8)
        return true
    }

    /// Identifiers starting with `prefix` from ONE accessibility snapshot, in tree order. No NSPredicate.
    func storyIDs(prefix: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            let id = node.identifier
            if id.hasPrefix(prefix), !found.contains(id) { found.append(id) }
            for child in node.children { walk(child) }
        }
        walk(root)
        return found
    }

    /// The first identifier with `prefix` that exists and is hittable now; nil when none.
    func storyFirstHittable(prefix: String) -> String? {
        for id in storyIDs(prefix: prefix) {
            let e = element(id)
            if e.exists && e.isHittable { return id }
        }
        return nil
    }

    /// The first hittable slider whose identifier does not start with `excludingPrefix`; nil when none.
    func storyFirstSlider(excludingPrefix: String) -> XCUIElement? {
        for s in app.sliders.allElementsBoundByIndex where s.exists && s.isHittable && !s.identifier.hasPrefix(excludingPrefix) {
            return s
        }
        return nil
    }

    /// Read-only UX audit of the current screen (one accessibility snapshot). Records every finding in
    /// `r.uxIssues` and attaches `<story>-ux` with the counts and up to 30 lines.
    func uxAudit(story: String, _ r: StoryRecorder) {
        var lines: [String] = []
        var counts: [String: Int] = [:]
        var interactive = 0
        var sheets = 0
        func flag(_ category: String, _ detail: String) {
            counts[category, default: 0] += 1
            let line = "\(category): \(detail)"
            r.uxIssues.append(line)
            lines.append(line)
        }
        let window = app.windows.firstMatch.frame
        let interactiveTypes: [XCUIElement.ElementType] = [.button, .slider, .textField, .switch, .menuButton]
        func walk(_ node: XCUIElementSnapshot, _ depth: Int) {
            if depth > 80 { return }
            let type = node.elementType
            if type == .sheet { sheets += 1 }
            if type == .alert { flag("alert", "'\(node.label)'") }
            if interactiveTypes.contains(type) {
                interactive += 1
                let f = node.frame
                let id = node.identifier
                let label = node.label
                let desc = "\(type) id='\(id)' label='\(label)' frame=\(f)"
                if id.isEmpty { flag("no-identifier", desc) }
                if label.isEmpty {
                    flag("no-label", desc)
                } else if label.contains(".") && !label.contains(" ") {
                    flag("symbol-like-label", desc)
                }
                if label.hasSuffix("\u{2026}") { flag("ellipsis-label", desc) }
                if !f.isEmpty {
                    if f.width < 44 || f.height < 44 { flag("under-44pt", desc) }
                    if !window.isEmpty && (f.minX < window.minX - 1 || f.minY < window.minY - 1
                                           || f.maxX > window.maxX + 1 || f.maxY > window.maxY + 1) {
                        flag("outside-window", desc)
                    }
                }
            }
            for child in node.children { walk(child, depth + 1) }
        }
        if let root = try? app.snapshot() {
            walk(root, 0)
        } else {
            flag("no-snapshot", "app.snapshot() failed")
        }
        if sheets > 1 { flag("multiple-sheets", "\(sheets) sheets on screen") }

        var out = ["story: \(story)", "interactive elements: \(interactive)", "issues: \(lines.count)"]
        for key in counts.keys.sorted() { out.append("  \(key): \(counts[key] ?? 0)") }
        out.append(contentsOf: lines.prefix(30))
        let attachment = XCTAttachment(string: out.joined(separator: "\n"))
        attachment.name = "\(story)-ux"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Attaches `<story>-steps` and appends `story | PASS/FAIL | taps | ux issues` to the summary file.
    func finishStory(_ name: String, _ r: StoryRecorder) {
        let lines = r.steps.map { ($0.1 ? "ok     " : "MISSED ") + $0.0 }
        let attachment = XCTAttachment(string: lines.isEmpty ? "no steps" : lines.joined(separator: "\n"))
        attachment.name = "\(name)-steps"
        attachment.lifetime = .keepAlways
        add(attachment)
        let failed = r.steps.contains { !$0.1 }
        appendStorySummaryLine("\(name) | \(failed ? "FAIL" : "PASS") | \(r.taps) | \(r.uxIssues.count)")
    }
}
