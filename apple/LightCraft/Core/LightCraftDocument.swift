import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import LightCraftKit

extension UTType {
    /// A LightCraft library: a package directory with `catalog.snap`, `Originals/`, ... (`.lightcraftlibrary`).
    static let lightCraftLibrary = UTType(exportedAs: "ca.hologram.lightcraft.library", conformingTo: .package)
}

/// Package document for a LightCraft library. The Rust engine owns the real state; the document keeps a
/// working copy of the package folder under Caches and writes it back through `fileWrapper`.
final class LightCraftDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = URL

    static var readableContentTypes: [UTType] { [.lightCraftLibrary] }
    static var writableContentTypes: [UTType] { [.lightCraftLibrary] }

    /// The thread-safe engine object; snapshots call it directly without hopping to the main actor.
    private(set) var handle: LibraryHandle
    private let workingDir: URL
    /// True when the document was created by `init()` or opened empty; the demo launch argument seeds it.
    private let isEmptyAtOpen: Bool
    /// Set when the working directory could not be created or opened (the document then runs in memory).
    private let openError: String?

    @MainActor private var modelStorage: LibraryModel?

    /// Editor state for this document, created on first use on the main actor.
    @MainActor var model: LibraryModel {
        if let existing = modelStorage { return existing }
        // Demo mode: reopen an empty library with the engine's procedural photos before the model reads it.
        let seeding = AppSettings.isDemo && isEmptyAtOpen
        if seeding { reopenSeeded() }
        let created = LibraryModel(handle: handle)
        if let openError { created.lastError = openError }
        modelStorage = created
        if seeding {
            Task { @MainActor in await DemoContent.seed(created) }
        }
        return created
    }

    /// New (empty) library.
    init() {
        AppSettings.registerDefaults()
        let dir = Self.makeWorkingDir()
        workingDir = dir
        let opened = Self.openHandle(dir, seedDemo: false)
        handle = opened.handle
        openError = opened.error
        isEmptyAtOpen = true
    }

    /// Opens a library package from disk. A "New" document is written by `init()` and then reopened here,
    /// so a library with 0 photos counts as new (demo seeding).
    required init(configuration: ReadConfiguration) throws {
        AppSettings.registerDefaults()
        guard configuration.file.isDirectory else { throw CocoaError(.fileReadCorruptFile) }
        let dir = Self.makeWorkingDir()
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try configuration.file.write(to: dir, options: .atomic, originalContentsURL: nil)
        workingDir = dir
        let opened = Self.openHandle(dir, seedDemo: false)
        handle = opened.handle
        openError = opened.error
        isEmptyAtOpen = opened.handle.state().photoCount == 0
    }

    // MARK: Saving

    /// Called by SwiftUI for every autosave, possibly off the main thread. Flushes the engine journal and
    /// returns the working directory; the engine is internally locked, so this never touches the history.
    func snapshot(contentType: UTType) throws -> URL {
        try handle.persist()
        return workingDir
    }

    func fileWrapper(snapshot: URL, configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        let items = try FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil)
        // The lock file belongs to the running engine; thumbs/ is a cache that is rebuilt on open.
        let skipped: Set<String> = ["catalog.lock", "thumbs", ".DS_Store"]
        for item in items where !skipped.contains(item.lastPathComponent) {
            let child = try FileWrapper(url: item, options: [])
            child.preferredFilename = item.lastPathComponent
            wrapper.addFileWrapper(child)
        }
        return wrapper
    }

    // MARK: Helpers

    /// Closes the handle and reopens the same folder with the demo photos. The engine seeds only a library
    /// it creates, so the (empty) working copy is removed first.
    @MainActor private func reopenSeeded() {
        try? handle.close()
        try? FileManager.default.removeItem(at: workingDir)
        handle = Self.openHandle(workingDir, seedDemo: true).handle
    }

    private static func makeWorkingDir() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("Libraries", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).lightcraftlibrary", isDirectory: true)
    }

    /// Opens the library at `dir`; falls back to the in-memory demo library so the app never has no handle.
    private static func openHandle(_ dir: URL, seedDemo: Bool) -> (handle: LibraryHandle, error: String?) {
        do {
            return (try LibraryHandle.open(dir: dir.path, seedDemo: seedDemo), nil)
        } catch {
            return (LibraryHandle.inMemoryDemo(), "The library could not be opened: \(error.localizedDescription)")
        }
    }
}
