import Foundation
import Testing
import LightCraftKit
import UIKit

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

    @Test func movedOriginalCanBeRelinkedBeforePixelCommands() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lc-relink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let moved = root.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let oldFile = old.appendingPathComponent("original.jpg")
        let movedFile = moved.appendingPathComponent("original.jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        try #require(image.jpegData(compressionQuality: 0.9)).write(to: oldFile)
        let catalog = root.appendingPathComponent("Catalog.lightcraftlibrary")
        let handle = try LibraryHandle.open(dir: catalog.path, seedDemo: false)
        let report = try handle.execute(id: "library.import", paramsJson: "{\"paths\":[\"\(oldFile.path)\"],\"mode\":\"add\"}")
        let imported = try #require((try JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])?["imported"] as? [UInt64])
        let id = try #require(imported.first)
        try handle.close()
        try FileManager.default.moveItem(at: oldFile, to: movedFile)
        let reopened = try LibraryHandle.open(dir: catalog.path, seedDemo: false)
        _ = try reopened.execute(id: "photo.relink", paramsJson: "{\"id\":\(id),\"path\":\"\(movedFile.path)\"}")
        let rendered = try reopened.render(id: id, maxW: 64, maxH: 64, before: false, draft: true, applyCrop: true)
        #expect(rendered.width > 0 && rendered.height > 0)
    }
}
