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
/// images of the current source, the source list, thumbnails, originals, and writing edits back.
@MainActor @Observable
final class PhotosLibrary {
    /// Format identifier of the adjustment data LightCraft stores with an edited asset.
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
    @ObservationIgnored private var rawIDs: [String]?
    @ObservationIgnored private let cache = PHCachingImageManager()
    @ObservationIgnored private var forwarder: PhotoChangeForwarder?

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
                Task { @MainActor in self?.reload(rescanRaw: true) }
            }
            forwarder = f
            PHPhotoLibrary.shared().register(f)
        }
        reload(rescanRaw: true)
    }

    // MARK: Fetching

    nonisolated private static func options() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    private func reload(rescanRaw: Bool) {
        guard isAuthorized else { return }
        sources = Self.loadSources(rawCount: rawIDs?.count)
        if !sources.contains(where: { $0.id == currentID }) { currentID = "all" }
        applyCurrent()
        loaded = true
        if rescanRaw { scanRaw() }
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

    /// Finds the RAW assets in the background (PhotoKit has no RAW smart album).
    private func scanRaw() {
        Task { [weak self] in
            let ids: [String] = await Task.detached(priority: .utility) {
                var out: [String] = []
                PHAsset.fetchAssets(with: Self.options()).enumerateObjects { asset, _, _ in
                    if Self.rawResource(of: PHAssetResource.assetResources(for: asset)) != nil { out.append(asset.localIdentifier) }
                }
                return out
            }.value
            guard let self else { return }
            let changed = ids != self.rawIDs
            self.rawIDs = ids
            guard changed else { return }
            var assets: [PHAsset] = []
            PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in assets.append(a) }
            self.rawAssets = assets.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            self.sources = Self.loadSources(rawCount: ids.count)
            if self.currentID == "raw" { self.applyCurrent() }
        }
    }

    private static func loadSources(rawCount: Int?) -> [PhotosSource] {
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
        guard let fetch else { return nil }
        for i in 0..<fetch.count where fetch.object(at: i).localIdentifier == localID { return i }
        return nil
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

    nonisolated private static func request(_ manager: Unchecked<PHCachingImageManager>, _ asset: Unchecked<PHAsset>, _ size: CGSize, _ options: PHImageRequestOptions) async -> Unchecked<UIImage?> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Unchecked<UIImage?>, Never>) in
            manager.value.requestImage(for: asset.value, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true, image != nil { return }
                continuation.resume(returning: Unchecked(value: image))
            }
        }
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
        return url
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

    /// The develop settings (JSON) LightCraft stored with the asset when it edited it; nil for an untouched
    /// photo or an edit made by another app.
    func adjustmentJSON(localID: String) async -> String? {
        guard let asset = Self.asset(withIdentifier: localID), asset.hasAdjustments,
              let input = await Self.editingInput(for: asset),
              let adj = input.adjustmentData, adj.formatIdentifier == Self.formatIdentifier else { return nil }
        return String(data: adj.data, encoding: .utf8)
    }

    /// Writes a rendered JPEG and the settings back into the asset (iOS asks the person to confirm).
    func writeBack(localID: String, jpeg: Data, settingsJSON: String) async throws {
        guard let asset = Self.asset(withIdentifier: localID) else { throw Self.error("The photo is no longer in your Photos library.") }
        guard let input = await Self.editingInput(for: asset) else { throw Self.error("Photos could not open the photo for editing.") }
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(formatIdentifier: Self.formatIdentifier, formatVersion: "1", data: Data(settingsJSON.utf8))
        try Self.writeRendered(jpeg, to: output.renderedContentURL, type: output.defaultRenderedContentType)
        try await Self.apply(Unchecked(value: asset), Unchecked(value: output))
    }

    nonisolated private static func apply(_ asset: Unchecked<PHAsset>, _ output: Unchecked<PHContentEditingOutput>) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset.value).contentEditingOutput = output.value
        }
    }

    /// JPEG as is; transcoded when Photos expects another type (HEIC).
    nonisolated private static func writeRendered(_ jpeg: Data, to url: URL, type: UTType?) throws {
        guard let type, type != .jpeg, type.conforms(to: .heic),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            try jpeg.write(to: url, options: .atomic)
            return
        }
        CGImageDestinationAddImageFromSource(dest, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw error("The edited photo could not be encoded.") }
    }

    /// Photos' own "Revert to Original".
    func revertToOriginal(localID: String) async throws {
        guard let asset = Self.asset(withIdentifier: localID) else { throw Self.error("The photo is no longer in your Photos library.") }
        try await Self.revert(Unchecked(value: asset))
    }

    nonisolated private static func revert(_ asset: Unchecked<PHAsset>) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset.value).revertAssetContentToOriginal()
        }
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

    nonisolated static func error(_ message: String) -> NSError {
        NSError(domain: "LightCraft", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
