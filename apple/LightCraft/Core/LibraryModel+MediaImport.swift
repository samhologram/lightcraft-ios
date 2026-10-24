import SwiftUI
import UIKit
import Photos
import ObjectiveC
import UniformTypeIdentifiers
@preconcurrency import LightCraftKit

// Media in: Files / iCloud Drive / any file provider, drag and drop and paste. The Photos library is the
// library, so imported files are ADDED TO PHOTOS (`PHAssetCreationRequest`, files copied, never moved);
// the engine catalog then picks them up through the normal open path (`engineID(forAsset:)`). An `.xmp`
// sidecar with the same base name is applied to the new photo with the engine's `photo.readMetadataFromFile`.

/// UI state of the media importer, attached to its `LibraryModel` (an extension cannot add stored properties).
@MainActor @Observable
final class MediaImportState {
    var showImporter = false
    var isImporting = false
    var progress = ""
}

private nonisolated(unsafe) let mediaImportStateKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

/// Result of one import run.
struct MediaImportReport: Sendable {
    var imported = 0
    var failed: [(name: String, reason: String)] = []
    var sidecarsApplied = 0
    var sidecarNotes: [String] = []
    var albumTitle: String?

    var summary: String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var lines: [String] = []
        if imported > 0 {
            var line = "Imported \(plural(imported, "photo")) into Photos"
            if let albumTitle { line += " (album “\(albumTitle)”)" }
            lines.append(line)
        }
        if sidecarsApplied > 0 { lines.append("Applied \(plural(sidecarsApplied, "XMP sidecar"))") }
        lines.append(contentsOf: sidecarNotes)
        if !failed.isEmpty {
            lines.append("\(failed.count) failed:\n" + failed.map { "\($0.name): \($0.reason)" }.joined(separator: "\n"))
        }
        if lines.isEmpty { lines.append("No photos to import") }
        return lines.joined(separator: "\n")
    }
}

/// A file received by drop or paste, already copied out of the provider's temporary location.
struct DroppedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            DroppedMedia(url: try LibraryModel.stageReceived(received.file))
        }
    }
}

extension LibraryModel {
    var mediaImport: MediaImportState {
        if let existing = objc_getAssociatedObject(self, mediaImportStateKey) as? MediaImportState { return existing }
        let created = MediaImportState()
        objc_setAssociatedObject(self, mediaImportStateKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return created
    }

    // MARK: Entry points

    /// Content types of the Files importer: RAW (incl. DNG), TIFF, JPEG, PNG, HEIC/HEIF, other images
    /// iOS decodes, and `.xmp` sidecars.
    static var mediaContentTypes: [UTType] {
        var types: [UTType] = [.rawImage, .tiff, .jpeg, .png, .heic, .heif, .webP, .image]
        if let dng = UTType("com.adobe.raw-image") { types.append(dng) }
        types.append(UTType(filenameExtension: "xmp") ?? .xml)
        types.append(.folder)
        return types
    }

    /// Presents the Files importer (File ▸ Import Photos…, ⌘K, grid toolbar, empty state).
    func presentMediaImport() {
        if mode != .grid { commitEdits(); mode = .grid }
        mediaImport.showImporter = true
    }

    /// Pastes the images / files on the system pasteboard (reading it shows iOS's paste prompt).
    func importFromPasteboard() async {
        let providers = UIPasteboard.general.itemProviders.map { Unchecked(value: $0) }
        var urls: [URL] = []
        for provider in providers {
            if let url = await Self.loadFile(from: provider) { urls.append(url) }
        }
        guard !urls.isEmpty else { lastNotice = "There is no image or file to paste."; return }
        await importMedia(urls)
    }

    // MARK: Import

    /// Stages the (security-scoped) files, adds them to Photos (into the current album when it is a user
    /// album), applies matching XMP sidecars and shows the summary in `lastNotice`.
    @discardableResult
    func importMedia(_ urls: [URL], intoCurrentAlbum: Bool = true) async -> MediaImportReport {
        var report = MediaImportReport()
        guard !urls.isEmpty, !mediaImport.isImporting else { return report }
        let state = mediaImport
        state.isImporting = true
        state.progress = "Preparing…"
        defer { state.isImporting = false; state.progress = "" }

        guard await photos.ensureAddAccess() else {
            lastError = "LightCraft is not allowed to add photos. Allow it in Settings > Privacy & Security > Photos."
            return report
        }
        if samplesMode { lastNotice = "Import is not available in the demo samples."; return report }

        // Stage off the main thread: copies (and iCloud downloads, via file coordination) can be slow.
        let staged = await Task.detached(priority: .userInitiated) { Self.stage(urls) }.value
        defer { for root in Set(staged.files.map { Self.stagingRoot(of: $0) }) { try? FileManager.default.removeItem(at: root) } }
        report.failed.append(contentsOf: staged.failures)

        var items: [PhotosLibrary.MediaImportItem] = []
        var sidecars: [String: URL] = [:]
        var buckets: [String: (raw: [URL], other: [URL])] = [:]
        var order: [String] = []
        for file in staged.files {
            switch PhotosLibrary.mediaKind(of: file) {
            case .sidecar:
                sidecars[file.deletingPathExtension().lastPathComponent.lowercased()] = file
            case .photo(let raw):
                let key = file.deletingPathExtension().lastPathComponent.lowercased()
                if buckets[key] == nil { order.append(key) }
                if raw { buckets[key, default: ([], [])].raw.append(file) } else { buckets[key, default: ([], [])].other.append(file) }
            case .convertible:
                state.progress = "Converting \(file.lastPathComponent)…"
                do {
                    let tiff = try await Task.detached(priority: .userInitiated) { try PhotosLibrary.transcodeToTIFF(file) }.value
                    let key = tiff.deletingPathExtension().lastPathComponent.lowercased()
                    if buckets[key] == nil { order.append(key) }
                    buckets[key, default: ([], [])].other.append(tiff)
                } catch {
                    report.failed.append((file.lastPathComponent, error.localizedDescription))
                }
            case .unsupported:
                report.failed.append((file.lastPathComponent, "Unsupported file type"))
            }
        }
        for key in order {
            guard let bucket = buckets[key] else { continue }
            var raws = bucket.raw
            var others = bucket.other
            if let raw = raws.first, let other = others.first {
                // RAW+JPEG pair: the JPEG is the photo, the RAW its alternate resource.
                raws.removeFirst(); others.removeFirst()
                items.append(.init(primary: other, alternate: raw, stem: key, fullName: raw.lastPathComponent.lowercased()))
            }
            for url in raws + others {
                items.append(.init(primary: url, alternate: nil, stem: key, fullName: url.lastPathComponent.lowercased()))
            }
        }
        for i in items.indices {
            items[i].sidecar = sidecars[items[i].stem] ?? sidecars[items[i].fullName]
        }

        let album = intoCurrentAlbum ? photos.currentUserAlbum : nil
        var created: [(local: String, item: PhotosLibrary.MediaImportItem)] = []
        for (n, item) in items.enumerated() {
            state.progress = "Importing \(n + 1) of \(items.count)…"
            do {
                let local = try await photos.addToLibrary(item, albumID: album?.id)
                created.append((local, item))
                report.imported += 1
            } catch {
                let ns = error as NSError
                if ns.domain == "PHPhotosErrorDomain" && ns.code == 3072 { continue }   // declined
                report.failed.append((item.displayName, error.localizedDescription))
            }
        }
        if report.imported > 0, album != nil { report.albumTitle = album?.title }

        for (local, item) in created {
            guard let xmp = item.sidecar else { continue }
            state.progress = "Applying \(xmp.lastPathComponent)…"
            do {
                try await applySidecar(xmp, toAsset: local, originalName: item.displayName)
                report.sidecarsApplied += 1
            } catch {
                report.sidecarNotes.append("\(xmp.lastPathComponent) not applied: \(error.localizedDescription)")
            }
        }

        let usedStems = Set(items.flatMap { [$0.stem, $0.fullName] })
        let unmatched = sidecars.keys.filter { !usedStems.contains($0) }.count
        if unmatched > 0 {
            report.sidecarNotes.append("\(unmatched) XMP file\(unmatched == 1 ? "" : "s") had no matching photo (use Import Presets for presets)")
        }
        lastNotice = report.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return report
    }

    /// Registers the new asset with the engine (caching its original) and has the engine read the XMP:
    /// the sidecar is placed next to the app-owned source copy for `photo.readMetadataFromFile`.
    /// The result is persisted in LightCraft's edit settings; the Photos asset is unchanged.
    private func applySidecar(_ xmp: URL, toAsset local: String, originalName: String) async throws {
        let id = try await engineID(forAsset: local)
        let folder = AppEnvironment.copyFolder(for: local)
        let stem = (originalName as NSString).deletingPathExtension
        // The engine's naming preference decides which one it reads: IMG_1.xmp or IMG_1.CR3.xmp.
        let copies = [folder.appendingPathComponent(stem + ".xmp"), folder.appendingPathComponent(originalName + ".xmp")]
        defer { for c in copies { try? FileManager.default.removeItem(at: c) } }
        for c in copies {
            try? FileManager.default.removeItem(at: c)
            try FileManager.default.copyItem(at: xmp, to: c)
        }
        select(id)
        guard let result = execute("photo.readMetadataFromFile", ["ids": [id]]) else {
            throw PhotosLibrary.error(lastError ?? "The engine could not read it.")
        }
        let read = (result["read"] as? NSNumber)?.intValue ?? (result["read"] as? [Any])?.count ?? 0
        if read == 0 {
            let reason = (result["failed"] as? [Any])?.first.map { "\($0)" } ?? "nothing to read"
            throw PhotosLibrary.error(reason)
        }
    }

    // MARK: Staging

    /// Folder every staged file lives under: `<tmp>/LightCraftImport-<uuid>/<n>/<file>`.
    nonisolated private static let stagingPrefix = "LightCraftImport-"

    nonisolated static func stagingRoot(of url: URL) -> URL {
        var current = url
        while current.pathComponents.count > 1 {
            if current.lastPathComponent.hasPrefix(stagingPrefix) { return current }
            current = current.deletingLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }

    nonisolated private static func isStaged(_ url: URL) -> Bool { url.path.contains("/\(stagingPrefix)") }

    /// Copies a file a drop / paste handed over (valid only inside the callback) to a temp folder.
    nonisolated static func stageReceived(_ file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("0", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: dest)
        return dest
    }

    /// Copies picked items out of their security scope (iCloud Drive placeholders are downloaded by the
    /// coordinated read), expanding folders. Files already staged (drop / paste) are used as they are.
    nonisolated static func stage(_ urls: [URL]) -> (files: [URL], failures: [(name: String, reason: String)]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        var files: [URL] = []
        var failures: [(name: String, reason: String)] = []
        var counter = 0
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        func copy(_ source: URL) {
            counter += 1
            let sub = root.appendingPathComponent("\(counter)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                let dest = sub.appendingPathComponent(source.lastPathComponent)
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                    do { try FileManager.default.copyItem(at: readable, to: dest) } catch { copyError = error }
                }
                if let e = coordinationError ?? copyError { throw e }
                files.append(dest)
            } catch {
                failures.append((source.lastPathComponent, error.localizedDescription))
            }
        }
        for url in urls {
            if isStaged(url) { files.append(url); continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if isDir(url) {
                let children = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let child = children?.nextObject() as? URL {
                    if !isDir(child) { copy(child) }
                }
            } else {
                copy(url)
            }
        }
        return (files, failures)
    }

    /// Loads one pasteboard item as a staged file (image data gets a file name from its type).
    nonisolated private static func loadFile(from box: Unchecked<NSItemProvider>) async -> URL? {
        let provider = box.value
        let types = provider.registeredContentTypes
        guard let type = types.first(where: { $0.conforms(to: .image) }) ?? types.first(where: { $0.conforms(to: .item) && !$0.conforms(to: .url) }) else {
            return nil
        }
        let suggested = provider.suggestedName
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                // The file is deleted when this handler returns: copy it now.
                var name = url.lastPathComponent
                if url.pathExtension.isEmpty, let ext = type.preferredFilenameExtension {
                    name = ((suggested ?? "Pasted Photo") as NSString).deletingPathExtension + "." + ext
                }
                do {
                    let folder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
                        .appendingPathComponent("0", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let dest = folder.appendingPathComponent(name)
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Views

/// Files importer, drop target and progress overlay for the grid. Attach once to the grid.
struct MediaImportModifier: ViewModifier {
    let model: LibraryModel
    @Bindable private var state: MediaImportState
    @State private var targeted = false

    init(model: LibraryModel) {
        self.model = model
        self.state = model.mediaImport
    }

    func body(content: Content) -> some View {
        content
            .dropDestination(for: DroppedMedia.self) { items, _ in
                guard !items.isEmpty else { return false }
                let urls = items.map(\.url)
                Task { await model.importMedia(urls) }
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.tint, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("photos.dropTarget")
                }
            }
            .overlay {
                if state.isImporting {
                    ProgressView(state.progress)
                        .padding(20)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("photos.importing")
                }
            }
            .background {
                Color.clear.fileImporter(isPresented: $state.showImporter, allowedContentTypes: LibraryModel.mediaContentTypes, allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): Task { await model.importMedia(urls) }
                    case .failure(let error): model.lastError = error.localizedDescription
                    }
                }
            }
    }
}

/// "Import" button for the grid toolbar / menus (`control.importMedia`).
struct MediaImportButton: View {
    let model: LibraryModel
    var body: some View {
        Button { model.presentMediaImport() } label: { Label("Import", systemImage: "square.and.arrow.down") }
            .accessibilityIdentifier("control.importMedia")
    }
}

/// System paste button (no pasteboard prompt) that imports pasted images / files.
struct MediaPasteButton: View {
    let model: LibraryModel
    var body: some View {
        PasteButton(payloadType: DroppedMedia.self) { items in
            let urls = items.map(\.url)
            Task { await model.importMedia(urls) }
        }
        .accessibilityIdentifier("control.pasteMedia")
    }
}
