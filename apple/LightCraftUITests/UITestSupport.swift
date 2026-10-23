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
        continueAfterFailure = false
        let mode = dark ? "dark" : "light"
        prefix = "\(isPad ? "ipad" : "iphone")-\(mode)"
        notes = []
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app = XCUIApplication()
        app.launchArguments = ["-LightCraftDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "The app did not launch")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60), "The app has no window")
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
