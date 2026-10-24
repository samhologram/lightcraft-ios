import Foundation
import os
@preconcurrency import LightCraftKit

private let openLog = Logger(subsystem: "ca.hologram.lightcraft", category: "photos")

/// The Photos library as the library: opening an asset registers (once) its cached original in the engine
/// catalog, edits run on that engine photo, and leaving the loupe writes changed settings back to Photos.
extension LibraryModel {
    var photos: PhotosLibrary { AppEnvironment.shared.photos }

    // MARK: Start

    /// Requests Photos access and raises `demoReady` once the grid can show. In demo mode a denied or
    /// empty Photos library falls back to the engine's procedural samples.
    func bootstrap() async {
        if let error = AppEnvironment.shared.catalogError { lastError = error }
        let p = photos
        if p.status == .notDetermined { await p.requestAccess() }
        if AppSettings.isDemo && (!p.isAuthorized || p.count == 0) {
            await useSamples()
            return
        }
        isDemoReady = true
    }

    /// Switches this window to the engine's in-memory demo photos (editable, no write-back).
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
        do {
            let id = try await engineID(forAsset: local)
            select(id)
            openLocalID = local
            openIndex = index
            baselineJSON = try? handle.developJson(id: id)
            mode = .loupe
        } catch {
            openLog.error("open failed for \(local, privacy: .public): \(String(describing: error), privacy: .public)")
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

    private func engineID(forAsset local: String) async throws -> UInt64 {
        let env = AppEnvironment.shared
        if let known = env.map.engineID(for: local), handle.photoInfo(id: known) != nil,
           let file = cachedFile(for: local), FileManager.default.fileExists(atPath: file.path) {
            // The catalog stores absolute paths, and iOS moves the app's data container on every reinstall
            // or update: point the engine at the file's current path once per launch, or every command that
            // reads pixels fails with "No such file or directory".
            if !env.relinked.contains(known) {
                let json = Self.encode(["id": known, "path": file.path]) ?? "{}"
                let handle = self.handle
                _ = try? await Task.detached(priority: .userInitiated) {
                    try handle.execute(id: "photo.relink", paramsJson: json)
                }.value
                env.relinked.insert(known)
            }
            return known
        }
        // First time: cache the original (RAW when there is one) and register it in place. Write it beside
        // the cache and swap it in only once complete: deleting first left the engine (which may already know
        // this file) pointing at nothing whenever the write then failed.
        let folder = AppEnvironment.originalsFolder(for: local)
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let written = try await photos.writeOriginal(localID: local, into: staging)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(written.lastPathComponent)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: written)
        } else {
            try FileManager.default.moveItem(at: written, to: file)
        }
        if let known = env.map.engineID(for: local), handle.photoInfo(id: known) != nil {
            // The engine already has this photo (its cached file was missing or moved): point it at the file.
            let json = Self.encode(["id": known, "path": file.path]) ?? "{}"
            let handle = self.handle
            _ = try? await Task.detached(priority: .userInitiated) { try handle.execute(id: "photo.relink", paramsJson: json) }.value
            env.relinked.insert(known)
            return known
        }
        let settings = await photos.adjustmentJSON(localID: local)
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

    private func cachedFile(for local: String) -> URL? {
        let folder = AppEnvironment.originalsFolder(for: local)
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?.first
    }

    // MARK: Writing back

    /// When the open photo's settings changed since it was opened (or last saved), renders it at full
    /// resolution and writes it back into the asset together with the settings.
    func commitEdits() {
        guard !samplesMode, let local = openLocalID, let id = state.active ?? openEngineID(),
              let baseline = baselineJSON,
              let json = try? handle.developJson(id: id), json != baseline else { return }
        baselineJSON = json
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            await self?.writeBack(local: local, engineID: id, settings: json)
        }
    }

    private func openEngineID() -> UInt64? {
        guard let local = openLocalID else { return nil }
        return AppEnvironment.shared.map.engineID(for: local)
    }

    private func writeBack(local: String, engineID id: UInt64, settings: String) async {
        writeBackCount += 1
        defer { writeBackCount -= 1 }
        guard let info = handle.photoInfo(id: id) else { return }
        guard let jpeg = await exportJPEG(id, longEdge: Int(max(info.width, info.height)), quality: 92) else { return }
        do {
            try await photos.writeBack(localID: local, jpeg: jpeg, settingsJSON: settings)
            savedCount += 1
        } catch {
            // Declining the system's confirmation is not a failure worth an alert.
            let ns = error as NSError
            if ns.domain == "PHPhotosErrorDomain" && ns.code == 3072 { return }
            lastError = "Saving to Photos failed: \(error.localizedDescription)"
        }
    }

    /// Waits for the write-backs in flight.
    func waitForWriteBack() async { await writeTask?.value }

    /// Photos' "Revert to Original" for the open photo; the engine settings are reset too.
    func revertToOriginal() {
        guard !samplesMode, let local = openLocalID else { return }
        run("develop.reset")
        baselineJSON = state.active.flatMap { try? handle.developJson(id: $0) }
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            writeBackCount += 1
            defer { writeBackCount -= 1 }
            do {
                try await photos.revertToOriginal(localID: local)
                savedCount += 1
            } catch {
                let ns = error as NSError
                if !(ns.domain == "PHPhotosErrorDomain" && ns.code == 3072) {
                    lastError = "Revert failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
