import SwiftUI
import CoreGraphics
@preconcurrency import LightCraftKit

/// RGBA8 premultiplied pixels from the engine. Plain `Sendable` data, so it can cross actors;
/// `CGImage` is not `Sendable` and is only built on the main actor.
struct PixelBuffer: Sendable {
    let width: Int
    let height: Int
    let data: Data

    init?(_ image: RenderedImage) {
        let w = Int(image.width), h = Int(image.height)
        guard w > 0, h > 0, image.rgba.count >= w * h * 4 else { return nil }
        width = w
        height = h
        data = Data(image.rgba)
    }

    /// Wraps the bytes without copying them (CGDataProvider keeps the `Data` alive).
    func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)
    }
}

extension LibraryModel {
    /// Key part that changes when a photo's thumbnail is stale. Views pass it to `.task(id:)`.
    func thumbnailVersion(_ id: UInt64) -> Int {
        (thumbnailVersions[id] ?? 0) &+ undoRedoTick &* 1000
    }

    /// Thumbnail with the long edge `edge` pixels, cached. Rendered off the main actor.
    func thumbnail(_ id: UInt64, edge: Int) async -> CGImage? {
        let key = "\(id)-\(edge)-\(thumbnailVersion(id))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let handle = self.handle
        let pixels: PixelBuffer? = await Task.detached(priority: .utility) {
            guard let image = try? handle.thumbnail(id: id, edge: UInt32(max(16, edge))) else { return nil }
            return PixelBuffer(image)
        }.value
        guard !Task.isCancelled, let image = pixels?.makeCGImage() else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    /// Renders photo `id` to fit `size` (pixels). `before` shows the original; `draft` is faster and rougher;
    /// `applyCrop` false renders the whole frame (the crop overlay draws the crop over it).
    func render(_ id: UInt64, size: CGSize, before: Bool, draft: Bool, applyCrop: Bool = true) async -> CGImage? {
        let w = UInt32(min(max(size.width.rounded(), 16), 8192))
        let h = UInt32(min(max(size.height.rounded(), 16), 8192))
        let handle = self.handle
        let pixels: PixelBuffer? = await Task.detached(priority: draft ? .userInitiated : .utility) {
            guard let image = try? handle.render(id: id, maxW: w, maxH: h, before: before, draft: draft, applyCrop: applyCrop) else { return nil }
            return PixelBuffer(image)
        }.value
        guard !Task.isCancelled else { return nil }
        return pixels?.makeCGImage()
    }

    /// JPEG bytes for export / share. Runs off the main actor.
    func exportJPEG(_ id: UInt64, longEdge: Int, quality: Int) async -> Data? {
        let handle = self.handle
        do {
            return try await Task.detached(priority: .userInitiated) {
                try handle.exportJpeg(id: id, longEdge: UInt32(max(16, longEdge)), quality: UInt32(min(max(quality, 1), 100)))
            }.value
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
