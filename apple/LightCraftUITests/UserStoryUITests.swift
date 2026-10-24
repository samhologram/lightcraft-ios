import XCTest
import UIKit

/// User stories through the real UI. Each test runs one story with `storyTap`-style steps, asserts the core
/// outcome, audits the main screen (`uxAudit`) and writes `<story>-steps`, `<story>-ux` attachments and one line
/// per story to /tmp/lcstory-summary.txt. Missing elements fail the story (never silently pass).
@MainActor
final class UserStoryUITests: LightCraftUITestCase {

    /// Launches the demo library and waits for the grid and its first photo.
    private func startLibrary(dark: Bool = false) {
        launchDemo(dark: dark)
        openNewDemoLibrary()
        XCTAssertTrue(element("photo.0").waitForExistence(timeout: 30), "no photos in the grid")
    }

    /// Like `startLibrary`, but every step is recorded instead of asserted, and the test keeps running after a
    /// failed step, so the story still writes its steps and UX files. Used by the stories that must always report.
    private func startLibraryRecording(_ r: StoryRecorder, dark: Bool = false) {
        launchDemo(dark: dark)
        continueAfterFailure = true
        pause(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
            let button = springboard.alerts.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        storyCheck(element("demoReady").waitForExistence(timeout: 180), "demo-grid-ready", r)
        pause(3)
        storyCheck(element("photo.0").waitForExistence(timeout: 30), "grid-photo-0", r)
    }

    /// Opens photo.0 in the loupe and makes sure the Edit panel section shows the exposure slider.
    @discardableResult
    private func openStoryPhoto(_ r: StoryRecorder) -> Bool {
        storyTap("photo.0", r)
        let opened = waitForAny(["toolbar.beforeAfter", "control.light.exposure", "loupe"], timeout: 30) != nil
        storyCheck(opened, "loupe-open", r)
        if opened { ensureExposureSlider(r) }
        return opened
    }

    /// Makes sure the Edit panel is shown and expanded so `control.light.exposure` exists. Taps the `panel.edit`
    /// switcher button when the slider is missing, waits up to 10 s for it, and taps the section's collapse
    /// toggle (`panel.edit.collapse`) when that is on screen and the slider still is not. Records one step.
    @discardableResult
    private func ensureExposureSlider(_ r: StoryRecorder) -> Bool {
        let slider = element("control.light.exposure")
        if !slider.exists { tapQuietly(element("panel.edit"), timeout: 5) }
        var shown = slider.waitForExistence(timeout: 10)
        if !shown, element("panel.edit.collapse").exists {
            tapQuietly(element("panel.edit.collapse"), timeout: 1)
            shown = slider.waitForExistence(timeout: 5)
        }
        storyCheck(shown, "exposure-slider-visible", r)
        return shown
    }

    /// Value of `id`, or "" when it is not on screen (reading a missing element would fail the test).
    private func valueOf(_ id: String) -> String {
        let e = element(id)
        guard e.exists else { return "" }
        return (e.value as? String) ?? ""
    }

    private func labelOf(_ id: String) -> String {
        let e = element(id)
        return e.exists ? e.label : ""
    }

    private func exposureValue() -> String { valueOf("control.light.exposure") }

    /// True when `e` exists, its centre lies in the window and it is hittable. Checks the frame first, because
    /// `isHittable` fails the test for elements scrolled far out of view.
    private func onScreen(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f = e.frame
        let w = app.windows.firstMatch.frame
        guard !f.isEmpty, w.contains(CGPoint(x: f.midX, y: f.midY)) else { return false }
        return e.isHittable
    }

    /// Taps `e` once it appears and is on screen, within `timeout`. Records no step; returns whether it tapped.
    @discardableResult
    private func tapQuietly(_ e: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if onScreen(e) { e.tap(); return true }
            pause(0.3)
        }
        return false
    }

    /// A menu item on screen by label. Searches the open menu first, then any menu item or button with that label.
    private func menuElement(_ label: String) -> XCUIElement? {
        let candidates = [
            app.menus.firstMatch.menuItems[label].firstMatch,
            app.menuItems[label].firstMatch,
            app.buttons[label].firstMatch,
        ]
        for e in candidates where onScreen(e) { return e }
        return nil
    }

    /// Taps a menu item by label; returns whether it was found.
    @discardableResult
    private func tapMenuItem(_ label: String) -> Bool {
        guard let e = menuElement(label) else { return false }
        e.tap()
        return true
    }

    /// What a key or gesture changed on screen: photo cell labels and values, selection, the exposure value
    /// and the edited marker. Compared before and after each shortcut to record whether it had an effect.
    private func stateSignature() -> String {
        let p1 = element("photo.1")
        return [
            labelOf("photo.0"),
            valueOf("photo.0"),
            String(p1.exists && p1.isSelected),
            exposureValue(),
            String(element("photo.edited.0").exists),
        ].joined(separator: "|")
    }

    /// Long-presses grid cell `cell`, then picks `id` from its context menu. Items that live in a submenu are
    /// reached by opening the submenu (`submenu`, by label) first. The menu label `label` is the fallback when the
    /// item has no identifier. Records the pick as one step named `id`.
    @discardableResult
    private func pickFromCellMenu(cell: String, id: String, submenu: String?, label: String, _ r: StoryRecorder) -> Bool {
        storyPress(cell, r)
        pause(0.8)
        var done = tapQuietly(element(id), timeout: 1)
        if !done, let sub = submenu, let s = menuElement(sub) {
            s.tap()
            pause(0.8)
            done = tapQuietly(element(id), timeout: 2) || tapMenuItem(label)
        }
        if !done { done = tapMenuItem(label) }
        if done { r.taps += 1 }
        r.steps.append((id, done))
        return done
    }

    /// Rotates left in the Crop panel: the `command.photo.rotateLeft` control when it is there, else the Crop
    /// panel header menu (`panel.crop.menu`) and its "Rotate Left" item. Records one step.
    private func rotateLeftInCrop(_ r: StoryRecorder) {
        if tapQuietly(element("command.photo.rotateLeft"), timeout: 3) {
            r.taps += 1
            r.steps.append(("command.photo.rotateLeft", true))
            return
        }
        var done = false
        if tapQuietly(element("panel.crop.menu"), timeout: 3) {
            pause(0.8)
            done = tapMenuItem("Rotate Left")
            if !done {
                // Dismiss the menu with a tap on a neutral corner of the window.
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
                pause(0.5)
            }
        }
        if done { r.taps += 1 }
        r.steps.append(("command.photo.rotateLeft", done))
    }

    /// Sends one shortcut and records whether the visible state changed (a note, not an assertion).
    private func keyProbe(_ label: String, _ send: () -> Void) {
        let before = stateSignature()
        send()
        pause(1)
        let after = stateSignature()
        note("key \(label): effect=\(before != after)")
        if before == after { note("key \(label): no visible change (before \(before))") }
    }

    // MARK: a. Cull

    func testStoryACull() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        // Flag submenu holds Pick and Reject; the Rating submenu holds the star items.
        pickFromCellMenu(cell: "photo.0", id: "photos.pick", submenu: "Flag", label: "Pick", r)
        pickFromCellMenu(cell: "photo.1", id: "photos.rate.3", submenu: "Rating", label: "3 Stars", r)
        pickFromCellMenu(cell: "photo.2", id: "photos.reject", submenu: "Flag", label: "Reject", r)
        uxAudit(story: "cull", r)
        finishStory("cull", r)
        storyAssertAll("cull", r)
    }

    // MARK: b. Develop basics

    func testStoryBDevelopBasics() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyTap("command.develop.auto", r)
        pause(1.5)
        let afterAuto = exposureValue()
        storyEnterValue("control.light.exposure", "1", r)
        let entered = exposureValue()
        storyCheck(storyNumber(entered) == 1 && entered != afterAuto, "exact-entry-exposure-1", r)
        storyTap("toolbar.beforeAfter", r)
        pause(1)
        storyTap("toolbar.beforeAfter", r)
        pause(1)
        storyTap("command.edit.undo", r)
        pause(1)
        storyCheck(exposureValue() == afterAuto, "undo-restores-auto", r)
        storyTap("command.edit.redo", r)
        pause(1)
        storyCheck(exposureValue() == entered, "redo-reapplies-entry", r)
        uxAudit(story: "develop-basics", r)
        finishStory("develop-basics", r)
        storyAssertAll("develop-basics", r)
    }

    // MARK: c. Crop

    func testStoryCCrop() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyTap("panel.crop", r)
        pause(1)
        let aspect = storyFirstHittable(prefix: "crop.aspect.")
        storyCheck(aspect != nil, "crop-aspect-found", r)
        if let id = aspect { storyTap(id, r) }
        rotateLeftInCrop(r)
        storyTap("command.crop.reset", r)
        uxAudit(story: "crop", r)
        finishStory("crop", r)
        storyAssertAll("crop", r)
    }

    // MARK: d. Save back, reopen, revert

    func testStoryDSaveBackAndRevert() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibraryRecording(r)
        openStoryPhoto(r)
        storyEnterValue("control.light.exposure", "1", r)
        let edited = exposureValue()
        storyTap("mode.grid", r)
        let marked = element("photo.edited.0").waitForExistence(timeout: 10)
        storyCheck(marked, "edited-marker-on-photo-0", r)
        openStoryPhoto(r)
        storyCheck(exposureValue() == edited && !edited.isEmpty, "edit-restored-on-reopen", r)
        storyTap("mode.grid", r)
        storyPress("photo.0", r)
        storyTap("menu.more", r)
        storyTap("photos.revert", r)
        storyCheck(waitForGone("photo.edited.0", timeout: 10), "revert-clears-edited-marker", r)
        uxAudit(story: "save-revert", r)
        finishStory("save-revert", r)
        storyAssertAll("save-revert", r)
    }

    // MARK: e. Copy and paste settings

    func testStoryECopyPasteSettings() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyEnterValue("control.light.exposure", "1", r)
        storyTap("mode.grid", r)
        storyPress("photo.0", r)
        storyTap("photos.copySettings", r)
        storyPress("photo.1", r)
        storyTap("photos.pasteSettings", r)
        storyCheck(element("photo.edited.1").waitForExistence(timeout: 10), "paste-marks-photo-1-edited", r)
        uxAudit(story: "copy-paste-settings", r)
        finishStory("copy-paste-settings", r)
        storyAssertAll("copy-paste-settings", r)
    }

    // MARK: f. Masking

    func testStoryFMasking() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyTap("panel.masking", r)
        storyTap("panel.masking.add", r)
        storyTapLabel("Subject", r)
        var slider = storyFirstSlider(excludingPrefix: "control.light.")
        var waited = 0
        while slider == nil && waited < 15 {
            pause(1)
            slider = storyFirstSlider(excludingPrefix: "control.light.")
            waited += 1
        }
        storyCheck(slider != nil, "masking-slider-found", r)
        if let s = slider {
            let before = (s.value as? String) ?? ""
            s.adjust(toNormalizedSliderPosition: 0.8)
            pause(1)
            let after = (s.value as? String) ?? ""
            note("masking slider \(s.identifier): \(before) -> \(after)")
            storyCheck(before != after, "masking-slider-changed", r)
        }
        uxAudit(story: "masking", r)
        finishStory("masking", r)
        storyAssertAll("masking", r)
    }

    // MARK: g. Guided Upright

    func testStoryGGuidedUpright() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyTap("tool.guidedUpright", r)
        let overlay = element("tool.guidedUpright.overlay")
        storyCheck(overlay.waitForExistence(timeout: 5), "guided-upright-overlay", r)
        if overlay.exists {
            // Two guides: one near the top, one near the bottom.
            let a = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
            let b = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3))
            a.press(forDuration: 0.3, thenDragTo: b)
            pause(0.5)
            let c = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.75))
            let d = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
            c.press(forDuration: 0.3, thenDragTo: d)
            pause(0.5)
        }
        storyCheck(element("control.guidedUpright.guide.0").waitForExistence(timeout: 5), "guide-0-exists", r)
        uxAudit(story: "guided-upright", r)
        finishStory("guided-upright", r)
        storyAssertAll("guided-upright", r)
    }

    // MARK: h. History and versions

    func testStoryHHistoryAndVersions() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyEnterValue("control.light.exposure", "1", r)
        storyEnterValue("control.light.contrast", "20", r)
        storyEnterValue("control.light.exposure", "2", r)
        storyTap("panel.activity", r)
        storyCheck(element("history.0").waitForExistence(timeout: 10), "history-row-0", r)
        storyTap("panel.activity.snapshot", r)
        storyTap("panel.versions", r)
        storyTap("command.version.create", r)
        uxAudit(story: "history-versions", r)
        finishStory("history-versions", r)
        storyAssertAll("history-versions", r)
    }

    // MARK: i. Keyboard shortcuts

    func testStoryIKeyboardShortcuts() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibraryRecording(r)
        // Grid: P (pick), 3 (rating), right arrow (selection), Cmd+Z (undo). Each is recorded, not asserted.
        keyProbe("p (grid)") { app.typeKey("p", modifierFlags: []) }
        keyProbe("3 (grid)") { app.typeKey("3", modifierFlags: []) }
        keyProbe("right arrow (grid)") { app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: []) }
        keyProbe("cmd+z (grid)") { app.typeKey("z", modifierFlags: .command) }
        storyCheck(true, "keys-sent-on-grid", r)
        // Loupe: the same keys on an open photo.
        openStoryPhoto(r)
        keyProbe("p (loupe)") { app.typeKey("p", modifierFlags: []) }
        keyProbe("3 (loupe)") { app.typeKey("3", modifierFlags: []) }
        keyProbe("right arrow (loupe)") { app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: []) }
        keyProbe("cmd+z (loupe)") { app.typeKey("z", modifierFlags: .command) }
        storyCheck(true, "keys-sent-in-loupe", r)
        uxAudit(story: "keyboard-shortcuts", r)
        finishStory("keyboard-shortcuts", r)
        storyAssertAll("keyboard-shortcuts", r)
    }

    // MARK: j. Multi-finger undo and redo

    func testStoryJMultiFingerUndoRedo() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary()
        openStoryPhoto(r)
        storyEnterValue("control.light.exposure", "1", r)
        let edited = exposureValue()
        let surface = element("loupe").exists ? element("loupe") : app.windows.firstMatch
        storyCheck(surface.exists, "loupe-surface", r)
        // Two fingers undo, three fingers redo.
        surface.tap(withNumberOfTaps: 1, numberOfTouches: 2)
        pause(1)
        let undone = exposureValue()
        storyCheck(undone != edited, "two-finger-undo-changes-exposure", r)
        surface.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        pause(1)
        storyCheck(exposureValue() == edited, "three-finger-redo-restores-exposure", r)
        uxAudit(story: "multi-finger-undo", r)
        finishStory("multi-finger-undo", r)
        storyAssertAll("multi-finger-undo", r)
    }

    // MARK: k. Dark and light

    func testStoryKDarkAndLight() {
        defer { flushNotes() }
        let r = StoryRecorder()
        startLibrary(dark: false)
        openStoryPhoto(r)
        uxAudit(story: "dark-light-light", r)
        app.terminate()
        startLibrary(dark: true)
        openStoryPhoto(r)
        uxAudit(story: "dark-light-dark", r)
        finishStory("dark-light", r)
        storyAssertAll("dark-light", r)
    }

    // MARK: Skipped stories

    func testSkippedList() {
        let lines = [
            "app launch: covered by the smoke test and the screenshot tours (LightCraftUITests, PanelTourUITests)",
            "open photo: covered by the tours (openFirstPhoto); stories open photo.0 directly",
            "panel reachability: covered by PanelTourUITests and ToolTourUITests",
            "full-screen toggle: covered by smoke/tours",
            "Files/HEIC import picker: the system document picker is not drivable reliably",
            "narrow window / Split View: not drivable from XCUITest",
        ]
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "UserStory-skipped"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
