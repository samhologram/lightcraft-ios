import XCTest

/// Photos-source app-copy editing and explicit Save Copy to Photos, plus denied / limited
/// permission states. Needs images in the simulator's Photos library; the runner sets the permission per
/// method with `simctl privacy` (testDenied* revoke, testLimited* reset, everything else grants).
@MainActor
final class DevicePhotosUITests: LightCraftUITestCase {
    private func firstCell() -> XCUIElement { element("photo.0") }

    private func openFirstPhoto() {
        XCTAssertTrue(firstCell().waitForExistence(timeout: 30), "no photos in the grid")
        firstCell().tap()
        XCTAssertTrue(element("loupe").waitForExistence(timeout: 60), "loupe not shown")
        pause(2)
    }

    /// Simulator-only synthetic Photos source. No PhotoKit write-back or source deletion.
    /// Runner must explicitly attest that photo.0 is a disposable, freshly seeded fixture.
    func testPhotosSourceEditCopyPersistsAndResets() {
        #if !targetEnvironment(simulator)
        XCTFail("This story is restricted to a synthetic simulator Photos library")
        return
        #endif
        guard ProcessInfo.processInfo.environment["LC_SYNTHETIC_PHOTOS"] == "1" else {
            XCTFail("Fixture prerequisite: isolated simulator seeded only with disposable images; set TEST_RUNNER_LC_SYNTHETIC_PHOTOS=1")
            return
        }
        launchPlain() // Never silently substitute engine samples for the Photos source.
        defer {
            let evidence = XCTAttachment(string: app.debugDescription)
            evidence.name = "photos-edit-copy-hierarchy"; evidence.lifetime = .keepAlways; add(evidence)
            flushNotes()
        }
        func awaitState(_ message: String, _ check: @escaping () -> Bool) {
            let predicate = NSPredicate { _, _ in check() }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: 15), .completed, message)
        }
        func exposure() -> Double? {
            let control = element("control.light.exposure")
            return storyNumber((control.value as? String) ?? "")
        }
        func openFixture() {
            XCTAssertTrue(firstCell().waitForExistence(timeout: 30), "Fixture: Photos grid must contain the synthetic source")
            XCTAssertTrue(firstCell().isHittable)
            firstCell().tap()
            XCTAssertTrue(element("loupe").waitForExistence(timeout: 60), "Fixture: source must open in the editor")
            ensureEditPanelOpen()
            if !element("control.light.exposure").isHittable {
                XCTAssertTrue(tap("toggleInspector"), "Exposure inspector must be reachable")
            }
            awaitState("Exposure must be editable", { self.element("control.light.exposure").isHittable })
        }
        func leaveEditor() {
            if !element("mode.grid").isHittable, element("panel.close").isHittable {
                XCTAssertTrue(tap("panel.close"))
            }
            XCTAssertTrue(tap("mode.grid"), "Leaving the editor must commit the app copy")
            XCTAssertTrue(firstCell().waitForExistence(timeout: 15))
        }
        openFixture()
        let baseline = exposure()
        XCTAssertNotNil(baseline, "Exposure must expose a numeric baseline")
        XCTAssertEqual(baseline, 0, "Fixture must be fresh and have no previous app-copy edits")
        let recorder = StoryRecorder()
        XCTAssertTrue(storyEnterValue("control.light.exposure", "1", recorder))
        awaitState("Exposure edit must change the app copy", { exposure() == 1 })
        leaveEditor()
        XCTAssertTrue(element("photo.edited.0").waitForExistence(timeout: 15), "The source tile must report its edited app copy")
        // A new process must restore persisted edits, not just retain the active editor model.
        app.terminate()
        app.launch()
        openFixture()
        awaitState("Exposure must restore after leaving and process relaunch", { exposure() == 1 })
        if !element("menu.more").isHittable, element("panel.close").isHittable {
            XCTAssertTrue(tap("panel.close"))
        }
        XCTAssertTrue(tap("menu.more"))
        let reset = element("photos.revert") // Stable identifier; current action is Reset Edit Copy.
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        XCTAssertEqual(reset.label, "Reset Edit Copy", "Reset must target the app copy, never the Photos original")
        reset.tap()
        leaveEditor()
        awaitState("Reset must clear the app-copy edited marker", { !self.element("photo.edited.0").exists })
        app.terminate()
        app.launch()
        openFixture()
        awaitState("Reset copy settings must persist after relaunch", { exposure() == baseline })
        note("UI verified Photos-source edit, persisted exposure, and copy-only reset. Original bytes, Documents/Edits source+JSON existence, and cache deletion are covered separately by EditCopyStore unit tests; no UI diagnostic exposes these files or Photos bytes.")
    }

    func testSaveCopyToPhotos() throws {
        launchDemo(dark: false)
        defer { flushNotes() }
        openNewDemoLibrary()
        let before = element("grid.count").exists ? element("grid.count").label : "n/a"
        openFirstPhoto()
        tap("share")
        tap("export.run")
        XCTAssertTrue(element("export.saveToPhotos").waitForExistence(timeout: 60), "export did not finish")
        shot("01-export")
        tap("export.saveToPhotos")
        if app.alerts.firstMatch.waitForExistence(timeout: 3) { note("alert: \(dismissAlert() ?? "")") }
        let saved = element("export.saved").waitForExistence(timeout: 30)
        note("grid count before: \(before); saved confirmation: \(saved)")
        shot("02-saved")
        XCTAssertTrue(saved, "Save Copy to Photos did not confirm")
    }

    // MARK: Permission states (the runner sets them with `simctl privacy` before each method; see run-ui-tests.sh)

    /// Photos access denied: the app (launched without -LightCraftDemo) shows the access-needed screen.
    func testDeniedState() throws {
        launchPlain()
        defer { flushNotes() }
        let found = waitForAny(["photos.openSettings", "photo.0", "photos.selectMore"], timeout: 60)
        shot("01-denied")
        guard found == "photos.openSettings" else {
            note("not in the denied state (found: \(found ?? "nothing")); the runner revokes access with simctl privacy revoke")
            try skipOrFail("Photos access is not denied in this run")
            return
        }
        XCTAssertFalse(element("photo.0").exists, "photos shown although access is denied")
        let title = app.staticTexts["Photos Access Needed"]
        if !title.exists { note("'Photos Access Needed' title not found") }
    }

    /// Denied access with -LightCraftDemo: falls back to the engine's sample photos (grid ready, editable).
    func testDeniedDemoFallback() throws {
        launchDemo(dark: false)
        defer { flushNotes() }
        openNewDemoLibrary()
        shot("01-fallback")
        if element("photos.openSettings").exists { note("denied screen shown instead of the sample fallback") }
        XCTAssertTrue(element("photo.0").waitForExistence(timeout: 30), "no sample photos after the fallback")
    }

    /// Limited access: the grid shows the limited banner with its Select More Photos button. simctl cannot
    /// set "limited" directly; the runner resets the permission so the system prompt appears, and this test
    /// chooses "Select Photos…" and picks a photo. If that cannot be driven the test fails when the runner set an expectation (LC_EXPECT_PHOTOS), else it is skipped.
    func testLimitedState() throws {
        launchPlain()
        defer { flushNotes() }
        pause(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Select Photos…", "Select Photos...", "Limit Access…", "Limit Access...", "Select Photos"] {
            let b = springboard.alerts.buttons[label].firstMatch
            if b.waitForExistence(timeout: 3) { shot("01-prompt"); b.tap(); break }
        }
        pause(3)
        if !element("photos.selectMore").exists {
            // The limited picker (PHPicker) runs out of process: look in the app first, then in springboard.
            var searched: [(String, XCUIApplication)] = [("app", app)]
            searched.append(("springboard", springboard))
            var picked = false
            for (name, host) in searched where !picked {
                let candidates: [XCUIElement] = [host.cells.firstMatch, host.images.firstMatch]
                if let pick = candidates.first(where: { $0.waitForExistence(timeout: 5) }), pick.isHittable {
                    pick.tap()
                    picked = true
                    note("limited picker photo found in \(name)")
                    for label in ["Add", "Done"] {
                        let b = host.buttons[label].firstMatch
                        if b.waitForExistence(timeout: 2) { b.tap(); break }
                    }
                }
            }
            if !picked {
                note("no photo in the limited picker (searched the app and springboard); the picker runs out of process, so its elements may not be exposed to this test")
            }
        }
        let found = waitForAny(["photos.selectMore", "photo.0"], timeout: 40)
        shot("02-limited")
        guard found != nil, element("photos.selectMore").waitForExistence(timeout: 10) else {
            note("limited banner not reached (found: \(found ?? "nothing")); simctl cannot grant limited access")
            try skipOrFail("could not reach the limited Photos state")
            return
        }
        XCTAssertTrue(element("photo.0").exists, "limited access shows no photos")
    }
}
