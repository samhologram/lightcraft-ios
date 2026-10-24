import Foundation
@preconcurrency import Photos
import PhotosUI
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A place the grid can show: a Photos smart album, a user album or the whole library.
struct PhotosSource: Identifiable, Hashable, Sendable {
    enum Group: Sendable { case library, smart, album }
    enum Kind: Hashable, Sendable { case all, favorites, raw, collection(String) }

    let id: String          // accessibility suffix: "all", "favorites", "raw", or the sanitized local identifier
    let title: String
    let symbol: String
    let count: Int?
    let kind: Kind
    let group: Group
}

/// Wraps a value PhotoKit hands out that is only used on the main actor again.
struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

/// Forwards PhotoKit's (off-main) change callbacks to the main actor.
private final class PhotoChangeForwarder: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}

/// The device's Photos library (PhotoKit) as LightCraft's library: authorization, a live fetch of the
/// images of the current source, the source list, thumbnails and read-only originals.
@MainActor @Observable
final class PhotosLibrary {
    /// Format identifier of adjustment data written by older LightCraft versions, read for migration only.
    nonisolated static let formatIdentifier = "ca.hologram.lightcraft"

    private(set) var status: PHAuthorizationStatus
    /// Bumps whenever the fetch changed, so views re-read `count` / `asset(at:)`.
    private(set) var revision = 0
    private(set) var sources: [PhotosSource] = []
    private(set) var currentID = "all"
    private(set) var count = 0
    /// True once the first fetch finished.
    private(set) var loaded = false

    @ObservationIgnored private var fetch: PHFetchResult<PHAsset>?
    @ObservationIgnored private var rawAssets: [PHAsset] = []
    @ObservationIgnored private var rawKnown: [String: Bool] = [:]
    @ObservationIgnored private var rawWanted: Range<Int>?
    @ObservationIgnored private var rawWorker: Task<Void, Never>?
    @ObservationIgnored private let cache = PHCachingImageManager()
    @ObservationIgnored private var forwarder: PhotoChangeForwarder?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var sourcesTask: Task<Void, Never>?

    var isAuthorized: Bool { status == .authorized || status == .limited }
    var isDenied: Bool { status == .denied || status == .restricted }
    var current: PhotosSource? { sources.first { $0.id == currentID } }

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        cache.allowsCachingHighQualityImages = false
        if isAuthorized { start() }
    }

    // MARK: Authorization

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if isAuthorized { start() }
    }

    /// Re-reads the status (after the user came back from Settings).
    func refreshStatus() {
        let new = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard new != status else { return }
        status = new
        if isAuthorized { start() }
    }

    func presentLimitedPicker() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        guard let top else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private func start() {
        if forwarder == nil {
            let f = PhotoChangeForwarder { [weak self] in
                Task { @MainActor in self?.scheduleReload() }
            }
            forwarder = f
            PHPhotoLibrary.shared().register(f)
        }
        reload()
    }

    /// Large libraries change constantly (iCloud sync and other apps): coalesce bursts of change
    /// notifications into one reload instead of one full reload per notification.
    private func scheduleReload() {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: Fetching

    nonisolated private static func options() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    private func reload() {
        guard isAuthorized else { return }
        // The grid's fetch is lazy and cheap; show it at once. Album counts cost one query per album, so
        // they are computed off the main thread (on launch the main thread must stay free: watchdog).
        applyCurrent()
        loaded = true
        reloadSources()
    }

    private func reloadSources() {
        sourcesTask?.cancel()
        let rawCount: Int? = rawKnown.isEmpty ? nil : rawAssets.count
        sourcesTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { Self.loadSources(rawCount: rawCount) }.value
            guard !Task.isCancelled, let self else { return }
            self.sources = loaded
            if !loaded.contains(where: { $0.id == self.currentID }) {
                self.currentID = "all"
                self.applyCurrent()
            }
        }
    }

    private func applyCurrent() {
        let o = Self.options()
        switch current?.kind ?? .all {
        case .all:
            fetch = PHAsset.fetchAssets(with: o)
            count = fetch?.count ?? 0
        case .favorites:
            o.predicate = NSPredicate(format: "mediaType == %d AND favorite == YES", PHAssetMediaType.image.rawValue)
            fetch = PHAsset.fetchAssets(with: o)
            count = fetch?.count ?? 0
        case .raw:
            fetch = nil
            count = rawAssets.count
        case .collection(let id):
            if let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
                fetch = PHAsset.fetchAssets(in: c, options: o)
            } else {
                fetch = PHAsset.fetchAssets(with: o)
            }
            count = fetch?.count ?? 0
        }
        revision += 1
    }

    /// RAW status of the photos the grid shows (PhotoKit has no RAW smart album, and reading every asset's
    /// resources is slow and allocates per asset: scanning a whole large library got the app killed for
    /// memory). Only the visible photos and the next `rawLookahead` are checked, in small background batches
    /// that follow the scroll; results are kept by local identifier. The RAW album lists the RAWs found so far.
    static let rawLookahead = 200

    /// Called by each grid cell as it appears.
    func noteVisible(_ index: Int) {
        guard let fetch, index >= 0, index < fetch.count else { return }
        rawWanted = index..<min(fetch.count, index + 1 + Self.rawLookahead)
        if rawWorker == nil { rawWorker = Task { [weak self] in await self?.drainRaw() } }
    }

    private func drainRaw() async {
        defer { rawWorker = nil }
        while let range = rawWanted, let fetch {
            rawWanted = nil
            let ids = range.compactMap { $0 < fetch.count ? fetch.object(at: $0).localIdentifier : nil }
                .filter { rawKnown[$0] == nil }
            var offset = 0
            while offset < ids.count, rawWanted == nil, !Task.isCancelled {
                let batch = Array(ids[offset..<min(offset + 40, ids.count)])
                offset += batch.count
                let flags = await Task.detached(priority: .utility) { Self.rawFlags(batch) }.value
                merge(rawFlags: flags)
            }
            if Task.isCancelled { return }
        }
    }

    nonisolated private static func rawFlags(_ ids: [String]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            autoreleasepool {
                out[asset.localIdentifier] = rawResource(of: PHAssetResource.assetResources(for: asset)) != nil
            }
        }
        return out
    }

    private func merge(rawFlags flags: [String: Bool]) {
        var foundNew = false
        for (id, isRaw) in flags {
            if rawKnown[id] == nil && isRaw { foundNew = true }
            rawKnown[id] = isRaw
        }
        guard foundNew else { return }
        let ids = rawKnown.compactMap { $0.value ? $0.key : nil }
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in assets.append(a) }
        rawAssets = assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        if let i = sources.firstIndex(where: { $0.id == "raw" }) {
            let s = sources[i]
            sources[i] = PhotosSource(id: s.id, title: s.title, symbol: s.symbol, count: rawAssets.count, kind: s.kind, group: s.group)
        }
        if currentID == "raw" { applyCurrent() }
    }

    nonisolated private static func loadSources(rawCount: Int?) -> [PhotosSource] {
        let images = options()
        func imageCount(_ c: PHAssetCollection) -> Int { PHAsset.fetchAssets(in: c, options: images).count }
        let total = PHAsset.fetchAssets(with: images).count
        let fav = PHFetchOptions()
        fav.predicate = NSPredicate(format: "mediaType == %d AND favorite == YES", PHAssetMediaType.image.rawValue)
        var out = [
            PhotosSource(id: "all", title: "All Photos", symbol: "photo.on.rectangle", count: total, kind: .all, group: .library),
            PhotosSource(id: "favorites", title: "Favorites", symbol: "heart", count: PHAsset.fetchAssets(with: fav).count, kind: .favorites, group: .library),
            PhotosSource(id: "raw", title: "RAW", symbol: "r.square", count: rawCount, kind: .raw, group: .library),
        ]
        let smart: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumRecentlyAdded, "clock"), (.smartAlbumScreenshots, "camera.viewfinder"),
            (.smartAlbumSelfPortraits, "person.crop.square"), (.smartAlbumPanoramas, "pano"), (.smartAlbumLivePhotos, "livephoto"),
            (.smartAlbumDepthEffect, "cube"), (.smartAlbumLongExposures, "timer"),
        ]
        for (subtype, symbol) in smart {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).enumerateObjects { c, _, _ in
                let n = imageCount(c)
                if n > 0 {
                    out.append(PhotosSource(id: sanitize(c.localIdentifier), title: c.localizedTitle ?? "Album", symbol: symbol, count: n, kind: .collection(c.localIdentifier), group: .smart))
                }
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in
            out.append(PhotosSource(id: sanitize(c.localIdentifier), title: c.localizedTitle ?? "Album", symbol: "rectangle.stack", count: imageCount(c), kind: .collection(c.localIdentifier), group: .album))
        }
        return out
    }

    func select(_ id: String) {
        guard id != currentID, sources.contains(where: { $0.id == id }) else { return }
        currentID = id
        applyCurrent()
    }

    nonisolated static func sanitize(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    // MARK: Assets

    func asset(at index: Int) -> PHAsset? {
        if case .raw = current?.kind {
            return index >= 0 && index < rawAssets.count ? rawAssets[index] : nil
        }
        guard let fetch, index >= 0, index < fetch.count else { return nil }
        return fetch.object(at: index)
    }

    func localIdentifier(at index: Int) -> String? { asset(at: index)?.localIdentifier }

    func index(of localID: String) -> Int? {
        if case .raw = current?.kind { return rawAssets.firstIndex { $0.localIdentifier == localID } }
        // Walking `object(at:)` faults in every asset: O(n) on the main thread for a large library.
        guard let fetch, let asset = Self.asset(withIdentifier: localID) else { return nil }
        let i = fetch.index(of: asset)
        return i == NSNotFound ? nil : i
    }

    static func asset(withIdentifier id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func toggleFavorite(at index: Int) async {
        guard let asset = asset(at: index) else { return }
        await Self.setFavorite(Unchecked(value: asset), !asset.isFavorite)
    }

    nonisolated private static func setFavorite(_ asset: Unchecked<PHAsset>, _ value: Bool) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset.value).isFavorite = value
        }
    }

    // MARK: Thumbnails

    /// The thumbnail of the asset at `index`, `edge` pixels on its long side; nil when unavailable.
    func thumbnail(at index: Int, edge: CGFloat) async -> UIImage? {
        guard let asset = asset(at: index) else { return nil }
        let size = CGSize(width: edge, height: edge)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let result = await Self.request(Unchecked(value: cache), Unchecked(value: asset), size, options)
        return result.value
    }

    /// Cancels the PhotoKit request when the awaiting task is cancelled (scrolled-off cells), so abandoned
    /// requests don't pile up in the image manager.
    private final class RequestToken: @unchecked Sendable {
        private let lock = NSLock()
        private var id: PHImageRequestID = PHInvalidImageRequestID
        private var cancelled = false
        private var finished = false
        private var continuation: CheckedContinuation<Unchecked<UIImage?>, Never>?

        /// Stores the continuation. False when the task was already cancelled: the continuation is then
        /// resumed with nil here and no request must be made.
        func install(_ continuation: CheckedContinuation<Unchecked<UIImage?>, Never>) -> Bool {
            lock.lock()
            if cancelled || finished {
                finished = true
                lock.unlock()
                continuation.resume(returning: Unchecked(value: nil))
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        func set(_ id: PHImageRequestID, manager: Unchecked<PHCachingImageManager>) {
            lock.lock()
            self.id = id
            let cancelNow = cancelled && !finished
            lock.unlock()
            if cancelNow { manager.value.cancelImageRequest(id) }
        }

        /// Cancels the PhotoKit request and resumes the waiter with nil (exactly once, even if PhotoKit
        /// never calls the result handler again).
        func cancel(manager: Unchecked<PHCachingImageManager>) {
            lock.lock()
            cancelled = true
            let id = self.id
            let live = !finished && id != PHInvalidImageRequestID
            let pending = finished ? nil : continuation
            if pending != nil { finished = true }
            continuation = nil
            lock.unlock()
            if live { manager.value.cancelImageRequest(id) }
            pending?.resume(returning: Unchecked(value: nil))
        }

        /// Resumes the waiter with `image`, the first time only (the result handler can be called more than once).
        func complete(_ image: UIImage?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: Unchecked(value: image))
        }
    }

    nonisolated private static func request(_ manager: Unchecked<PHCachingImageManager>, _ asset: Unchecked<PHAsset>, _ size: CGSize, _ options: PHImageRequestOptions) async -> Unchecked<UIImage?> {
        let token = RequestToken()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Unchecked<UIImage?>, Never>) in
                guard token.install(continuation) else { return }
                let id = manager.value.requestImage(for: asset.value, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true || info?[PHImageErrorKey] != nil {
                        token.complete(nil)
                        return
                    }
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true, image != nil { return }
                    token.complete(image)
                }
                token.set(id, manager: manager)
            }
        } onCancel: {
            token.cancel(manager: manager)
        }
    }

    /// Drops PhotoKit's cached thumbnails (memory warning).
    func trimCaches() {
        cache.stopCachingImagesForAllAssets()
    }

    // MARK: Originals

    /// Lightroom's rule: the RAW of a RAW+JPEG pair, otherwise the original (unedited) photo.
    nonisolated static func originalResource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return rawResource(of: resources)
            ?? resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .fullSizePhoto }
            ?? resources.first
    }

    nonisolated static func rawResource(of resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { r in
            (r.type == .alternatePhoto || r.type == .photo) && (UTType(r.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false)
        }
    }

    /// Writes the original of the asset to `folder/<original file name>` (network allowed) and returns it.
    func writeOriginal(localID: String, into folder: URL) async throws -> URL {
        guard let asset = Self.asset(withIdentifier: localID), let resource = Self.originalResource(of: asset) else {
            throw Self.error("The photo is no longer in your Photos library.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(resource.originalFilename)
        try? FileManager.default.removeItem(at: url)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await Self.writeResource(Unchecked(value: resource), to: url, options: options)
        if let type = UTType(resource.uniformTypeIdentifier), Self.needsNativeDecode(type) {
            let tiff = try await Task.detached(priority: .userInitiated) { try Self.transcodeHEIF(url) }.value
            try? FileManager.default.removeItem(at: url)
            return tiff
        }
        return url
    }

    /// The engine ships without an HEVC decoder (patents: upstream leaves it to the distributor), so HEIC/HEIF
    /// originals are decoded by iOS's own licensed decoder and handed to the engine as a 16-bit TIFF in the
    /// photo's colour space, with its metadata (EXIF, orientation) carried over. LZW keeps the file smaller.
    nonisolated static func transcodeHEIF(_ url: URL) throws -> URL { try transcodeToTIFF(url) }

    /// Non-RAW formats the engine has no decoder for in this build (`crates/codecs/src/sniff.rs`: HEIF needs
    /// HEVC, AVIF has no AV1 decoder); iOS decodes them natively and hands the engine a TIFF. JPEG, PNG,
    /// TIFF, WebP, BMP, GIF, PSD and RAW stay with the engine (RAW must be re-read non-destructively).
    nonisolated static func needsNativeDecode(_ type: UTType) -> Bool {
        if type.conforms(to: .rawImage) { return false }
        if type.conforms(to: .heif) || type.conforms(to: .heic) { return true }
        if let avif = UTType("public.avif"), type.conforms(to: avif) { return true }
        if let avis = UTType("public.avis"), type.conforms(to: avis) { return true }
        return false
    }

    /// ImageIO decode of any format iOS reads, written as a 16-bit LZW TIFF beside `url` (orientation,
    /// colour profile and EXIF kept).
    nonisolated static func transcodeToTIFF(_ url: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary) else {
            throw error("iOS could not decode this photo.")
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 16,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue) else {
            throw error("Not enough memory to convert this photo.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let deep = context.makeImage() else { throw error("Not enough memory to convert this photo.") }
        let out = url.deletingPathExtension().appendingPathExtension("tif")
        try? FileManager.default.removeItem(at: out)
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            throw error("Could not write the converted photo.")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]   // LZW
        // The source's depth (usually 8) would make the writer downconvert the 16-bit image.
        properties[kCGImagePropertyDepth] = nil
        properties[kCGImagePropertyHasAlpha] = nil
        CGImageDestinationAddImage(destination, deep, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw error("Could not write the converted photo.") }
        return out
    }

    nonisolated private static func writeResource(_ resource: Unchecked<PHAssetResource>, to url: URL, options: PHAssetResourceRequestOptions) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource.value, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    // MARK: Adjustments

    nonisolated private static func editingInput(for asset: PHAsset) async -> PHContentEditingInput? {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { $0.formatIdentifier == formatIdentifier }
        let box = Unchecked(value: asset)
        let result: Unchecked<PHContentEditingInput?> = await withCheckedContinuation { continuation in
            box.value.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: Unchecked(value: input))
            }
        }
        return result.value
    }

    /// Read old LightCraft adjustment data once when promoting a legacy photo to an app-owned copy.
    func adjustmentJSON(localID: String) async -> String? {
        guard let asset = Self.asset(withIdentifier: localID), asset.hasAdjustments,
              let input = await Self.editingInput(for: asset),
              let adj = input.adjustmentData, adj.formatIdentifier == Self.formatIdentifier else { return nil }
        return String(data: adj.data, encoding: .utf8)
    }

    // MARK: Save a copy

    /// Saves JPEG files as new photos (add-only access is enough).
    func saveCopies(_ files: [URL]) async throws {
        var access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if access == .notDetermined { access = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        guard access == .authorized || access == .limited else {
            throw Self.error("LightCraft is not allowed to add photos. Allow it in Settings > Privacy & Security > Photos.")
        }
        let items: [(Data, String)] = try files.map { (try Data(contentsOf: $0), $0.lastPathComponent) }
        try await Self.create(items)
    }

    nonisolated private static func create(_ items: [(Data, String)]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for (data, name) in items {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = name
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }
        }
    }

    // MARK: Import (Files, drop, paste)

    /// What an imported file is.
    enum MediaKind: Sendable, Equatable {
        case sidecar
        case photo(raw: Bool)        // Photos takes it as is
        case convertible             // iOS decodes it, Photos does not store it: converted to TIFF first
        case unsupported
    }

    nonisolated private static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "pef", "srw", "3fr", "iiq", "erf", "mrw", "x3f", "rwl", "dcr", "kdc",
    ]

    nonisolated static func mediaKind(of url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if ext == "xmp" { return .sidecar }
        let type = UTType(filenameExtension: ext)
        if rawExtensions.contains(ext) || type?.conforms(to: .rawImage) == true { return .photo(raw: true) }
        if let type, type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .tiff)
            || type.conforms(to: .heic) || type.conforms(to: .heif) || type.conforms(to: .gif) {
            return .photo(raw: false)
        }
        if let type, type.conforms(to: .image), let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 {
            return .convertible
        }
        return .unsupported
    }

    /// One Photos asset to create: `primary` is the `.photo` resource, `alternate` the RAW of a RAW+JPEG pair.
    struct MediaImportItem: Sendable {
        var primary: URL
        var alternate: URL?
        /// Lower-cased base name and full file name of the (RAW) original, for XMP sidecar matching.
        var stem: String
        var fullName: String
        var sidecar: URL?
        var displayName: String { (alternate ?? primary).lastPathComponent }
    }

    private final class CreatedID: @unchecked Sendable { var id: String? }

    /// True when LightCraft may add photos (asks the first time).
    func ensureAddAccess() async -> Bool {
        var access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if access == .notDetermined { access = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        return access == .authorized || access == .limited
    }

    /// Adds the file(s) to the Photos library (copying them: `shouldMoveFile = false`), into the user album
    /// `albumID` when given, and returns the new asset's local identifier.
    func addToLibrary(_ item: MediaImportItem, albumID: String?) async throws -> String {
        try await Self.createAsset(item, albumID: albumID)
    }

    nonisolated private static func createAsset(_ item: MediaImportItem, albumID: String?) async throws -> String {
        let created = CreatedID()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let main = PHAssetResourceCreationOptions()
            main.originalFilename = item.primary.lastPathComponent
            main.shouldMoveFile = false
            request.addResource(with: .photo, fileURL: item.primary, options: main)
            if let alternate = item.alternate {
                let alt = PHAssetResourceCreationOptions()
                alt.originalFilename = alternate.lastPathComponent
                alt.shouldMoveFile = false
                request.addResource(with: .alternatePhoto, fileURL: alternate, options: alt)
            }
            created.id = request.placeholderForCreatedAsset?.localIdentifier
            if let albumID, let placeholder = request.placeholderForCreatedAsset,
               let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
        guard let id = created.id else { throw error("Photos did not create the photo.") }
        return id
    }

    /// The user album the grid shows (smart albums and the library itself cannot take new photos).
    var currentUserAlbum: (id: String, title: String)? {
        guard let source = current, source.group == .album, case .collection(let id) = source.kind else { return nil }
        return (id, source.title)
    }

    nonisolated static func error(_ message: String) -> NSError {
        NSError(domain: "LightCraft", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
