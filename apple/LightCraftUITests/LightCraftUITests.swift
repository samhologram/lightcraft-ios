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
}
