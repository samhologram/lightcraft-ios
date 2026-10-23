import XCTest

/// Lightroom preset import: Presets > Import Presets... > pick `TestWarm.xmp` (seeded by run-ui-tests.sh into
/// the app's Documents, `crs:Exposure2012="+1.00"`, named "LC Test Warm") in the document picker, check the
/// summary, apply the preset, and check that exposure changed.
@MainActor
final class PresetImportUITests: LightCraftUITestCase {
    func testImportAndApplyLightroomPreset() throws {
        launchDemo(dark: false)
        defer { flushNotes() }
        openNewDemoLibrary()
        XCTAssertTrue(element("photo.0").waitForExistence(timeout: 30), "no photos in the grid")
        element("photo.0").tap()
        XCTAssertTrue(element("loupe").waitForExistence(timeout: 60), "loupe not shown")
        pause(2)

        // Exposure before the preset.
        ensureEditPanelOpen()
        let exposure = element("control.light.exposure")
        XCTAssertTrue(exposure.waitForExistence(timeout: 15), "no exposure slider")
        let before = exposure.value as? String ?? "?"

        tap("panel.presets")
        pause(1)
        shot("01-presets")
        XCTAssertTrue(tap("command.file.importPresets"), "no Import Presets button")

        // The system document picker: On My iPad/iPhone > LightCraft > TestWarm.xmp.
        pause(3)
        shot("02-picker")
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'TestWarm'")).firstMatch
        if !target.waitForExistence(timeout: 5) {
            for place in ["On My iPad", "On My iPhone", "LightCraft"] {
                let cell = app.cells[place].firstMatch
                let b = cell.exists ? cell : app.staticTexts[place].firstMatch
                if b.waitForExistence(timeout: 3) { b.tap(); pause(1) }
            }
            shot("02b-picker-browse")
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "TestWarm.xmp not found in the document picker")
        target.tap()
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 2) { open.tap() }

        let ok = element("notice.ok")
        XCTAssertTrue(ok.waitForExistence(timeout: 30), "no import summary")
        let summary = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        note("summary: \(summary)")
        shot("03-summary")
        XCTAssertTrue(summary.contains("Imported 1 preset"), "summary does not report 1 imported preset: \(summary)")
        XCTAssertFalse(summary.contains("failed"), "summary reports failures: \(summary)")
        ok.tap()
        pause(1)

        let preset = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'LC Test Warm'")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 10), "imported preset is not listed")
        shot("04-listed")
        preset.tap()
        pause(3)
        tap("panel.edit")
        XCTAssertTrue(exposure.waitForExistence(timeout: 10), "no exposure slider after applying")
        let after = exposure.value as? String ?? "?"
        note("exposure before: \(before) after: \(after)")
        shot("05-applied")
        XCTAssertNotEqual(before, after, "applying the preset did not change exposure")
    }
}
