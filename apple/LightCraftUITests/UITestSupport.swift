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

    /// Taps the system "Modify" confirmation iOS shows when an app changes a photo. Returns whether it showed.
    @discardableResult
    func confirmPhotoModification(timeout: TimeInterval = 20) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [springboard, app!] {
            let button = host.alerts.buttons["Modify"].firstMatch
            if button.waitForExistence(timeout: host === springboard ? timeout : 2) {
                shot("system-modify-alert")
                button.tap()
                return true
            }
        }
        note("no system Modify confirmation appeared")
        return false
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
