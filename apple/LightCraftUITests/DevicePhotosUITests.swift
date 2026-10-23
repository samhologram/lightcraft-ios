import XCTest

/// The Photos library as LightCraft's library (PhotoKit): grid, sources, editing with write-back to the
/// asset, restore from the stored adjustment data, revert, Save Copy to Photos, and the denied / limited
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

    private func exposureElement() -> XCUIElement {
        ensureEditPanelOpen()
        let e = element("control.light.exposure")
        _ = e.waitForExistence(timeout: 15)
        return e
    }

    private func backToGrid() {
        if !tap("mode.grid") { app.navigationBars.buttons.firstMatch.tap() }
        pause(2)
    }

    /// Reverts the open photo through the Photo menu and confirms iOS's prompt.
    private func revertOpenPhoto() {
        XCTAssertTrue(tap("menu.more"))
        pause(1)
        shot("revert-menu")
        XCTAssertTrue(tap("photos.revert"), "no Revert to Original item")
        confirmPhotoModification()
        pause(3)
    }

    func testEditWritesBackRestoresAndReverts() throws {
        launchDemo(dark: false, extraArguments: ["-LightCraftResetCache"])
        defer { flushNotes() }
        openNewDemoLibrary()
        shot("01-grid")
        note("grid count: \(element("grid.count").exists ? element("grid.count").label : "n/a (iPhone)")")
        if isPad { for s in ["album.favorites", "album.raw", "album.all"] { note("\(s): \(element(s).exists)") } }
        if element("photo.edited.0").exists {
            note("photo.0 was edited by an earlier run: reverting it first")
            openFirstPhoto()
            revertOpenPhoto()
            backToGrid()
            pause(3)
            XCTAssertFalse(element("photo.edited.0").exists, "could not revert the leftover edit")
            app.terminate()
            launchDemo(dark: false, extraArguments: ["-LightCraftResetCache"])
            openNewDemoLibrary()
        }

        // Edit: exposure.
        openFirstPhoto()
        let exposure = exposureElement()
        let before = exposure.value as? String ?? "?"
        exposure.swipeRight()
        pause(3)
        let edited = exposure.value as? String ?? "?"
        note("exposure before: \(before) edited: \(edited)")
        shot("02-edited")
        XCTAssertNotEqual(before, edited, "the slider did not move")

        // Leaving the loupe writes the edit back into the asset (iOS asks to confirm).
        if !isPad { app.swipeDown() }
        backToGrid()
        confirmPhotoModification()
        let saving = element("photos.saving")
        if saving.exists { waitForGone("photos.saving", timeout: 60) }
        pause(3)
        shot("03-after-save")
        XCTAssertTrue(element("photo.edited.0").waitForExistence(timeout: 20), "the asset in Photos has no adjustments after saving")

        // Fresh start (empty cache, as after a reinstall): the settings come back from the adjustment data.
        app.terminate()
        launchDemo(dark: false, extraArguments: ["-LightCraftResetCache"])
        openNewDemoLibrary()
        openFirstPhoto()
        let restored = exposureElement().value as? String ?? "?"
        note("exposure restored: \(restored)")
        shot("04-restored")
        XCTAssertEqual(restored, edited, "the edit was not restored from the adjustment data")

        // Revert to Original.
        revertOpenPhoto()
        shot("05-reverted")
        pause(2)
        let afterRevert = exposureElement().value as? String ?? "?"
        note("exposure after revert: \(afterRevert)")
        XCTAssertEqual(afterRevert, before, "exposure is not back to default after Revert to Original")
        backToGrid()
        waitForGone("photo.edited.0", timeout: 30)
        shot("06-grid-reverted")
        XCTAssertFalse(element("photo.edited.0").exists, "the asset still has adjustments after reverting")
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
