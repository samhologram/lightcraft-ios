import XCTest

/// Screenshot scenario in dark and light: new demo library, grid, open a photo, move a slider,
/// open panels, back to the grid.
@MainActor
final class LightCraftUITests: LightCraftUITestCase {
    func testScreenshotsDark() throws { try scenario(dark: true) }
    func testScreenshotsLight() throws { try scenario(dark: false) }

    private func scenario(dark: Bool) throws {
        launchDemo(dark: dark)
        defer { flushNotes() }
        openNewDemoLibrary()
        shot("01-grid")

        let firstPhoto = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.'")).firstMatch
        if firstPhoto.waitForExistence(timeout: 10) { firstPhoto.tap() } else { note("no photo.<id> cell") }
        if !element("loupe").waitForExistence(timeout: 20) { note("loupe not shown") }
        pause(3)
        shot("02-loupe")

        if !isPad { tap("panel.edit") }
        let exposure = element("control.light.exposure")
        if exposure.waitForExistence(timeout: 10) {
            exposure.swipeRight()
            pause(3)
        } else {
            note("control.light.exposure not found")
        }
        shot("03-edit")

        for panel in ["crop", "masking", "presets", "info"] {
            tap("panel.\(panel)")
            pause(2)
            if let alert = dismissAlert() { note("panel.\(panel): alert \(alert)") }
            shot("04-panel-\(panel)")
            if !isPad { app.swipeDown() }
        }

        if !tap("mode.grid") { app.navigationBars.buttons.firstMatch.tap() }
        pause(2)
        shot("05-back-to-grid")
    }

    /// Full-screen canvas: enter from the loupe, only the canvas and the exit button remain, exit restores the layout.
    func testFullScreenCanvas() throws {
        launchDemo(dark: false)
        defer { flushNotes("fullscreen-notes") }
        openNewDemoLibrary()

        let firstPhoto = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.'")).firstMatch
        let named = element("photo.0")
        if named.waitForExistence(timeout: 10) {
            named.tap()
        } else if firstPhoto.waitForExistence(timeout: 10) {
            note("photo.0 not found, opened the first photo.<id> cell")
            firstPhoto.tap()
        } else {
            XCTFail("no photo cell to open")
            return
        }
        XCTAssertTrue(element("loupe").waitForExistence(timeout: 20), "loupe not shown")
        pause(2)
        if !isPad { ensureEditPanelOpen() }

        XCTAssertTrue(element("control.fullscreen").waitForExistence(timeout: 10), "control.fullscreen missing")
        element("control.fullscreen").tap()

        XCTAssertTrue(element("control.fullscreen.exit").waitForExistence(timeout: 10), "control.fullscreen.exit missing")
        XCTAssertTrue(waitForGone("panel.edit", timeout: 10), "panel.edit still visible in full screen")
        XCTAssertTrue(element("loupe").exists, "canvas missing in full screen")
        XCTAssertFalse(element("control.fullscreen").exists, "toolbar button still visible in full screen")
        for id in ["filmstrip", "control.light.exposure", "mode.grid"] where element(id).exists {
            XCTFail("\(id) still visible in full screen")
        }
        if isPad && element("album.all").exists { note("sidebar item album.all still visible in full screen") }
        shot("fullscreen-on")

        element("control.fullscreen.exit").tap()
        XCTAssertTrue(element("panel.edit").waitForExistence(timeout: 10), "panel.edit did not return after exit")
        XCTAssertTrue(waitForGone("control.fullscreen.exit", timeout: 10), "exit button still visible")
        shot("fullscreen-off")
    }
}
