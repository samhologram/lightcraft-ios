import Foundation
import Testing
import LightCraftKit

/// Smoke tests of the Rust bridge as the app sees it.
struct BridgeSmokeTests {
    @Test func catalogsAreLoaded() {
        #expect(!commandCatalog().isEmpty)
        #expect(uiCommandCatalog().contains { $0.id == "panel.edit" })
        #expect(desktopMenuLayout().first?.title == "File")
        #expect(developControls().contains { $0.id == "light.exposure" })
    }

    @Test func demoLibraryRendersAndUndoes() throws {
        let handle = LibraryHandle.inMemoryDemo()
        let ids = handle.visiblePhotos()
        #expect(!ids.isEmpty)
        let id = try #require(ids.first)
        _ = try handle.execute(id: "library.select", paramsJson: "{\"ids\":[\(id)],\"active\":\(id)}")
        let before = handle.state().historyId
        _ = try handle.execute(id: "develop.set", paramsJson: "{\"values\":{\"light.exposure\":1.0}}")
        #expect(handle.state().historyId != before)
        #expect(handle.state().canUndo)
        let image = try handle.render(id: id, maxW: 256, maxH: 256, before: false, draft: true, applyCrop: true)
        #expect(image.rgba.count == Int(image.width * image.height * 4))
        _ = try handle.undo()
        #expect(handle.state().canRedo)
    }

    @Test func libraryPersistsOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lc-\(UUID().uuidString).lightcraftlibrary")
        defer { try? FileManager.default.removeItem(at: dir) }
        let handle = try LibraryHandle.open(dir: dir.path, seedDemo: true)
        let id = try #require(handle.visiblePhotos().first)
        _ = try handle.execute(id: "photo.rate", paramsJson: "{\"rating\":4,\"ids\":[\(id)]}")
        try handle.close()
        let reopened = try LibraryHandle.open(dir: dir.path, seedDemo: false)
        #expect(reopened.photoInfo(id: id)?.rating == 4)
    }
}
