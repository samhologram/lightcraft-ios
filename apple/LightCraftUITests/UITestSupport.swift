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

    /// Creates a new library from the launch scene and waits for the seeded demo photos.
    func openNewDemoLibrary() {
        pause(2)
        if let button = findNewLibraryButton() {
            button.tap()
            // The simulator's file provider sometimes fails the first creation ("Unable to Import
            // Document", DocumentManager error 1): dismiss and retry, three attempts in all.
            for attempt in 2...3 {
                let ok = app.alerts.buttons["OK"].firstMatch
                guard ok.waitForExistence(timeout: 8), !element("demoReady").exists else { break }
                note("New Library failed (\(app.alerts.firstMatch.label)); attempt \(attempt)")
                ok.tap()
                pause(3)
                findNewLibraryButton()?.tap()
            }
        } else {
            note("New Library button not found")
            shot("00-launch")
        }
        XCTAssertTrue(element("demoReady").waitForExistence(timeout: 180), "The demo library never became ready")
        pause(3)
    }

    func findNewLibraryButton() -> XCUIElement? {
        let deadline = Date().addingTimeInterval(45)
        let candidates: [@MainActor () -> XCUIElement] = [
            { self.app.buttons["New Library"].firstMatch },
            { self.app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'new library' OR label CONTAINS[c] 'create document' OR label CONTAINS[c] 'new document'")).firstMatch },
            { self.app.staticTexts["New Library"].firstMatch },
        ]
        while Date() < deadline {
            for make in candidates {
                let e = make()
                if e.exists && e.isHittable { return e }
            }
            pause(1)
        }
        return nil
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
