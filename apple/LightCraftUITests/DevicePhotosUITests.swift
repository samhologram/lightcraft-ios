import XCTest

/// The Photos library as LightCraft's library (PhotoKit): grid, sources, editing with write-back to the
/// asset, restore from the stored adjustment data, revert, Save Copy to Photos, and Lightroom preset import.
/// Needs photos access granted with `simctl privacy grant photos ca.hologram.lightcraft` and images in the
/// simulator's Photos library.
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
        if !isPad { tap("panel.edit") }
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
        if saving.exists { wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: saving)], timeout: 60) }
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
        backToGrid()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: element("photo.edited.0"))], timeout: 30)
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

    func testImportLightroomPreset() throws {
        launchDemo(dark: false)
        defer { flushNotes() }
        openNewDemoLibrary()
        openFirstPhoto()
        tap("panel.presets")
        pause(1)
        shot("01-presets")
        XCTAssertTrue(tap("command.file.importPresets"), "no Import Presets button")
        // The system document picker: On My iPad/iPhone > LightCraft > the .xmp.
        pause(3)
        shot("02-picker")
        let target = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'TestWarm'")).firstMatch
        if !target.waitForExistence(timeout: 5) {
            for place in ["On My iPad", "On My iPhone", "LightCraft"] {
                let b = app.cells[place].firstMatch.exists ? app.cells[place].firstMatch : app.staticTexts[place].firstMatch
                if b.waitForExistence(timeout: 3) { b.tap(); pause(1) }
            }
            shot("02b-picker-browse")
        }
        if target.waitForExistence(timeout: 8) {
            target.tap()
            let open = app.buttons["Open"].firstMatch
            if open.waitForExistence(timeout: 2) { open.tap() }
        } else { note("TestWarm.xmp not found in the picker") }
        let ok = element("notice.ok")
        XCTAssertTrue(ok.waitForExistence(timeout: 30), "no import summary")
        note("summary: " + app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        shot("03-summary")
        ok.tap()
        pause(1)
        let preset = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'LC Test Warm'")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 10), "imported preset is not listed")
        shot("04-listed")
        tap("panel.edit")
        let exposure = element("control.light.exposure")
        _ = exposure.waitForExistence(timeout: 10)
        let before = exposure.value as? String ?? "?"
        tap("panel.presets")
        if preset.waitForExistence(timeout: 5) { preset.tap() }
        pause(2)
        tap("panel.edit")
        _ = exposure.waitForExistence(timeout: 10)
        let after = exposure.value as? String ?? "?"
        note("exposure before: \(before) after: \(after)")
        shot("05-applied")
        XCTAssertNotEqual(before, after, "applying the preset did not change exposure")
    }
}
