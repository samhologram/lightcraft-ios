import Foundation
@preconcurrency import LightCraftKit

/// What every window shares: the internal engine catalog, the Photos library and the map between them.
///
/// The Photos library is the library the person sees. The engine catalog
/// (`Application Support/LightCraft/Catalog.lightcraftlibrary`) is an internal cache: it holds the engine
/// photo (settings, history, rating, flag...) of every Photos asset that was opened, referencing the cached
/// original in place.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let catalog: LibraryHandle
    let catalogError: String?
    let photos = PhotosLibrary()
    let map: AssetMap

    /// `Application Support/LightCraft`.
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LightCraft", isDirectory: true)
    }()

    private init() {
        AppSettings.registerDefaults()
        let dir = Self.supportDirectory
        // Test hook: start with an empty photo cache (as after a reinstall).
        if ProcessInfo.processInfo.arguments.contains("-LightCraftResetCache") {
            try? FileManager.default.removeItem(at: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(excluded)
        // The engine derives its memory budgets and the face-model folder (`<dir>/LightCraft/FaceModels`)
        // from this; it must run before the first `LibraryHandle.open`.
        configureRuntime(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                         supportDir: Self.supportDirectory.deletingLastPathComponent().path)
        let catalogDir = dir.appendingPathComponent("Catalog.lightcraftlibrary", isDirectory: true)
        do {
            catalog = try LibraryHandle.open(dir: catalogDir.path, seedDemo: false)
            catalogError = nil
        } catch {
            catalog = LibraryHandle.inMemoryDemo()
            catalogError = "The photo cache could not be opened: \(error.localizedDescription)"
        }
        map = AssetMap(file: dir.appendingPathComponent("assets.json"))
        relinkIfMoved(dir: dir)
    }

    /// The catalog stores absolute paths, and iOS moves the app's data container on every reinstall or
    /// update: when the container moved since the last launch, point every cached original at its current
    /// path (off the main thread). Without this, the photo the catalog restores as active (and any photo not
    /// reopened) fails every pixel-reading command with "No such file or directory".
    private func relinkIfMoved(dir: URL) {
        let marker = dir.appendingPathComponent("container-path.txt")
        let previous = try? String(contentsOf: marker, encoding: .utf8)
        guard previous != dir.path else { return }
        var jobs: [(UInt64, String)] = []
        for (local, id) in map.all {
            let folder = Self.originalsFolder(for: local)
            if let file = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?.first {
                jobs.append((id, file.path))
            }
        }
        relinked.formUnion(jobs.map(\.0))
        let handle = catalog
        Task.detached(priority: .utility) {
            for (id, path) in jobs {
                let json = "{\"id\":\(id),\"path\":\(Self.jsonString(path))}"
                _ = try? handle.execute(id: "photo.relink", paramsJson: json)
            }
            try? handle.persist()
            try? dir.path.write(to: marker, atomically: true, encoding: .utf8)
        }
    }

    nonisolated private static func jsonString(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
    }

    /// Engine photos relinked to their cached original's current path in this launch.
    var relinked: Set<UInt64> = []

    /// Where the original of an asset is cached (one folder per asset, the original file name inside).
    static func originalsFolder(for localID: String) -> URL {
        supportDirectory
            .appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(PhotosLibrary.sanitize(localID), isDirectory: true)
    }
}

/// PHAsset.localIdentifier -> engine photo id, persisted as JSON next to the catalog.
@MainActor
final class AssetMap {
    private let file: URL
    private var entries: [String: UInt64]

    init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: UInt64].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func engineID(for localID: String) -> UInt64? { entries[localID] }

    var all: [String: UInt64] { entries }

    func localID(for engineID: UInt64) -> String? { entries.first { $0.value == engineID }?.key }

    func set(_ engineID: UInt64, for localID: String) {
        entries[localID] = engineID
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }

    func remove(_ localID: String) {
        entries[localID] = nil
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}
