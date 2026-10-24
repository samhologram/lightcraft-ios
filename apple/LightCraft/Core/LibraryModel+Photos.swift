import Foundation
import os
@preconcurrency import LightCraftKit

private let openLog = Logger(subsystem: "ca.hologram.lightcraft", category: "photos")

/// Diagnostics also appended to `Library/Caches/lightcraft.log` in the app container, so test runs can
/// pull them with `simctl get_app_container` when `log stream` captures nothing. Capped at 1 MB.
nonisolated enum FileLog {
    private static let lock = NSLock()
    private static let url: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("lightcraft.log")

    static func write(_ line: String) {
        guard let url else { return }
        lock.lock(); defer { lock.unlock() }
        let text = "\(Date().ISO8601Format()) \(line)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > 1 << 20 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}

/// Photos supplies browsing and a read-only source. Edits use a persistent copy in LightCraft's folder.
extension LibraryModel {
    var photos: PhotosLibrary { AppEnvironment.shared.photos }

    func hasEditedCopy(for local: String) -> Bool {
        let _ = copyEditTick
        return EditCopyStore.record(in: AppEnvironment.copyFolder(for: local))?.edited == true
    }

    // MARK: Start

    /// Requests Photos access and raises `demoReady` once the grid can show. In demo mode a denied or
    /// empty Photos library falls back to the engine's procedural samples.
    func bootstrap() async {
        if let error = AppEnvironment.shared.catalogError { lastError = error }
        let relinkFailures = await AppEnvironment.shared.finishInitialRelink()
        if !relinkFailures.isEmpty {
            lastError = "Some cached originals could not be restored: \(relinkFailures.joined(separator: "; "))"
        }
        isCatalogReady = true
        let p = photos
        if p.status == .notDetermined { await p.requestAccess() }
        if AppSettings.isDemo && (!p.isAuthorized || p.count == 0) {
            await useSamples()
            return
        }
        isDemoReady = true
    }

    /// Switches this window to the engine's in-memory demo photos.
    func useSamples() async {
        handle = LibraryHandle.inMemoryDemo()
        samplesMode = true
        mode = .grid
        refresh()
        await DemoContent.seed(self)
    }

    // MARK: Opening

    /// Opens the asset at `index` of the current source in the loupe.
    func openPhoto(at index: Int) async {
        guard let local = photos.localIdentifier(at: index), !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        commitEdits()
        FileLog.write("open \(local) at \(index)")
        do {
            let id = try await engineID(forAsset: local)
            FileLog.write("opened \(local) as engine photo \(id)")
            select(id)
            openLocalID = local
            openIndex = index
            baselineJSON = try? handle.developJson(id: id)
            mode = .loupe
        } catch {
            openLog.error("open failed for \(local, privacy: .public): \(String(describing: error), privacy: .public)")
            FileLog.write("open failed for \(local): \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Moves the loupe to the neighbour in the current source (`delta` = +1 / -1).
    func stepPhoto(_ delta: Int) {
        guard !samplesMode, let index = openIndex else { return }
        let next = index + delta
        guard next >= 0, next < photos.count else { return }
        Task { await openPhoto(at: next) }
    }

    func engineID(forAsset local: String) async throws -> UInt64 {
        let env = AppEnvironment.shared
        let relinkFailures = await env.finishInitialRelink()
        if !relinkFailures.isEmpty {
            FileLog.write("startup relink failed: \(relinkFailures.joined(separator: "; "))")
        }
        let file = try await ensureEditCopy(for: local)
        let folder = AppEnvironment.copyFolder(for: local)
        if let known = env.map.engineID(for: local), let info = handle.photoInfo(id: known) {
            // The catalog may still point to a legacy cache or an old app-container path.
            let json = Self.encode(["id": known, "path": file.path]) ?? "{}"
            let handle = self.handle
            _ = try await Task.detached(priority: .userInitiated) {
                try handle.execute(id: "photo.relink", paramsJson: json)
            }.value
            if EditCopyStore.record(in: folder) == nil, let settings = try? handle.developJson(id: known) {
                try EditCopyStore.save(EditCopyRecord(sourceID: local, settingsJSON: settings, edited: info.edited), in: folder)
            }
            return known
        }
        let settings = try await initialCopySettings(for: local, in: folder)
        let json = Self.encode(["paths": [file.path], "mode": "add"]) ?? "{}"
        let handle = self.handle
        let result: String = try await Task.detached(priority: .userInitiated) {
            try handle.execute(id: "library.import", paramsJson: json)
        }.value
        let report = Self.decodeObject(result) ?? [:]
        let ids = ["imported", "restored"].flatMap { (report[$0] as? [Any]) ?? [] }.compactMap { ($0 as? NSNumber)?.uint64Value }
        guard let id = ids.first else {
            let failed = (report["failed"] as? [Any])?.first.map { "\($0)" } ?? "the engine did not register the photo"
            throw PhotosLibrary.error("Could not open the photo: \(failed)")
        }
        env.map.set(id, for: local)
        if let settings, let data = settings.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            select(id)
            _ = execute("develop.merge", ["settings": object, "label": "Restore LightCraft edits"])
        }
        refresh()
        try? handle.persist()
        return id
    }

    private func ensureEditCopy(for local: String) async throws -> URL {
        if let file = AppEnvironment.copyFile(for: local) { return file }
        let folder = AppEnvironment.copyFolder(for: local)
        if let legacy = AppEnvironment.legacyOriginal(for: local) {
            return try await Task.detached(priority: .userInitiated) {
                try EditCopyStore.copySource(legacy, into: folder)
            }.value
        }
        let staging = AppEnvironment.supportDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let original = try await photos.writeOriginal(localID: local, into: staging)
        return try await Task.detached(priority: .userInitiated) {
            try EditCopyStore.copySource(original, into: folder)
        }.value
    }

    /// Import old LightCraft adjustment data once, solely as a read-only migration source.
    private func initialCopySettings(for local: String, in folder: URL) async throws -> String? {
        if let record = EditCopyStore.record(in: folder), record.sourceID == local { return record.settingsJSON }
        let marker = folder.appendingPathComponent(".legacy-adjustment-checked")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let legacy = await photos.adjustmentJSON(localID: local)
        if let legacy {
            try EditCopyStore.save(EditCopyRecord(sourceID: local, settingsJSON: legacy, edited: true), in: folder)
        }
        try Data().write(to: marker, options: .atomic)
        return legacy
    }

    // MARK: App-owned copy persistence

    /// Save the editable settings beside the app-owned source copy. Never pass rendered content to PhotoKit.
    @discardableResult
    func persistCopySettings(for id: UInt64) -> Bool {
        guard !samplesMode, let local = AppEnvironment.shared.map.localID(for: id) else { return false }
        guard AppEnvironment.copyFile(for: local) != nil else {
            lastError = "The LightCraft edit copy for this photo is missing. Open it again to restore the source."
            return false
        }
        do {
            let settings = try handle.developJson(id: id)
            let edited = handle.photoInfo(id: id)?.edited ?? true
            try EditCopyStore.save(EditCopyRecord(sourceID: local, settingsJSON: settings, edited: edited),
                                   in: AppEnvironment.copyFolder(for: local))
            try handle.persist()
            if openLocalID == local { baselineJSON = settings }
            copyEditTick += 1
            return true
        } catch {
            lastError = "Saving the LightCraft edit copy failed: \(error.localizedDescription)"
            return false
        }
    }

    /// A final retry when leaving a photo or backgrounding. Normal edits save as they happen.
    func commitEdits() {
        guard !samplesMode, let local = openLocalID, let id = AppEnvironment.shared.map.engineID(for: local),
              let baseline = baselineJSON,
              let json = try? handle.developJson(id: id), json != baseline else { return }
        _ = persistCopySettings(for: id)
    }

    /// Paste into the mapped app copy, preserving the Photos asset and the previous loupe selection.
    func pasteSettings(toAssetAt index: Int) async {
        guard !samplesMode, let local = photos.localIdentifier(at: index) else { return }
        commitEdits()
        do {
            let id = try await engineID(forAsset: local)
            let previous = state.active
            select(id)
            let applied = run("develop.paste")
            if let previous, previous != id { select(previous) }
            guard applied else { return }
            _ = persistCopySettings(for: id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reset only the LightCraft copy's develop state to its unedited source pixels.
    func resetCopyToSource() {
        guard !samplesMode, let local = openLocalID,
              let id = AppEnvironment.shared.map.engineID(for: local) else { return }
        guard run("develop.reset") else { return }
        _ = persistCopySettings(for: id)
    }
}
