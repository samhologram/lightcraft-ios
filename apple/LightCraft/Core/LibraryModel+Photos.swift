import Foundation
@preconcurrency import LightCraftKit

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
           FileManager.default.fileExists(atPath: cachedFile(for: local)?.path ?? "") {
            return known
        }
        // First time: cache the original (RAW when there is one) and register it in place.
        let folder = AppEnvironment.originalsFolder(for: local)
        try? FileManager.default.removeItem(at: folder)
        let file = try await photos.writeOriginal(localID: local, into: folder)
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
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.first
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
