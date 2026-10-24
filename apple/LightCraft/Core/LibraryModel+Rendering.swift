import SwiftUI
import CoreGraphics
import UIKit
import os
import Darwin
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

    /// Thumbnail with the long edge `edge` pixels, cached. Rendered off the main actor, at most
    /// `renderGate.limit` at a time; a cancelled caller (scrolled-off cell) never reaches the engine.
    func thumbnail(_ id: UInt64, edge: Int) async -> CGImage? {
        let key = "\(id)-\(edge)-\(thumbnailVersion(id))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard await renderGate.acquire(priority: false) else { return nil }
        guard !Task.isCancelled else { await renderGate.release(priority: false); return nil }
        if let cached = thumbCache.object(forKey: key) { await renderGate.release(priority: false); return cached }
        let handle = self.handle
        let pixels: PixelBuffer? = await Task.detached(priority: .utility) {
            guard let image = try? handle.thumbnail(id: id, edge: UInt32(max(16, edge))) else { return nil }
            return PixelBuffer(image)
        }.value
        await renderGate.release(priority: false)
        guard !Task.isCancelled, let pixels, let image = pixels.makeCGImage() else { return nil }
        let isNew = thumbCache.object(forKey: key) == nil
        thumbCache.setObject(image, forKey: key, cost: pixels.width * pixels.height * 4)
        if isNew { thumbStats.noteInserted(bytes: pixels.width * pixels.height * 4) }
        return image
    }

    /// Renders photo `id` to fit `size` (pixels). `before` shows the original; `draft` is faster and rougher;
    /// `applyCrop` false renders the whole frame (the crop overlay draws the crop over it).
    /// Calls are coalesced: when a newer render of the same photo and mode is requested while this one waits for
    /// its turn, this one returns nil without touching the engine.
    func render(_ id: UInt64, size: CGSize, before: Bool, draft: Bool, applyCrop: Bool = true) async -> CGImage? {
        let w = UInt32(min(max(size.width.rounded(), 16), 8192))
        let h = UInt32(min(max(size.height.rounded(), 16), 8192))
        let slot = "\(id)-\(before)-\(draft)-\(applyCrop)"
        let generation = (renderGenerations[slot] ?? 0) &+ 1
        renderGenerations[slot] = generation
        guard await renderGate.acquire(priority: true) else { return nil }
        guard !Task.isCancelled, renderGenerations[slot] == generation else {
            await renderGate.release(priority: true)
            return nil
        }
        let handle = self.handle
        let pixels: PixelBuffer? = await Task.detached(priority: draft ? .userInitiated : .utility) {
            guard let image = try? handle.render(id: id, maxW: w, maxH: h, before: before, draft: draft, applyCrop: applyCrop) else { return nil }
            return PixelBuffer(image)
        }.value
        await renderGate.release(priority: true)
        if renderGenerations[slot] == generation { renderGenerations[slot] = nil }
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

// MARK: - Render concurrency

/// Counting semaphore for async code with two lanes. Priority (loupe) waiters are always served before
/// background (grid thumbnail) waiters, and background work may use at most `backgroundLimit` of the
/// `limit` permits, so the active edit never waits behind a queue of thumbnails.
/// `acquire` returns false when the waiting task was cancelled (no permit held: do not call `release`).
actor AsyncGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private let backgroundLimit: Int
    private var inUse = 0
    private var backgroundInUse = 0
    private var priorityWaiters: [Waiter] = []
    private var backgroundWaiters: [Waiter] = []

    init(limit: Int, backgroundLimit: Int) {
        self.limit = max(1, limit)
        self.backgroundLimit = max(1, min(backgroundLimit, self.limit))
    }

    private func canRun(priority: Bool) -> Bool {
        inUse < limit && (priority || backgroundInUse < backgroundLimit)
    }

    private func take(priority: Bool) {
        inUse += 1
        if !priority { backgroundInUse += 1 }
    }

    func acquire(priority: Bool) async -> Bool {
        if Task.isCancelled { return false }
        let queuesEmpty = priority ? priorityWaiters.isEmpty : (priorityWaiters.isEmpty && backgroundWaiters.isEmpty)
        if queuesEmpty, canRun(priority: priority) {
            take(priority: priority)
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let waiter = Waiter(id: id, continuation: continuation)
                if priority { priorityWaiters.append(waiter) } else { backgroundWaiters.append(waiter) }
                // A cancel that ran before the append found nothing to remove: catch it here.
                if Task.isCancelled { cancel(id) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        if let index = priorityWaiters.firstIndex(where: { $0.id == id }) {
            priorityWaiters.remove(at: index).continuation.resume(returning: false)
        } else if let index = backgroundWaiters.firstIndex(where: { $0.id == id }) {
            backgroundWaiters.remove(at: index).continuation.resume(returning: false)
        }
    }

    /// Returns a permit. Must pair with every `acquire` that returned true, with the same `priority`.
    func release(priority: Bool) {
        inUse -= 1
        if !priority { backgroundInUse -= 1 }
        pump()
    }

    private func pump() {
        while inUse < limit {
            if !priorityWaiters.isEmpty {
                take(priority: true)
                priorityWaiters.removeFirst().continuation.resume(returning: true)
            } else if !backgroundWaiters.isEmpty, canRun(priority: false) {
                take(priority: false)
                backgroundWaiters.removeFirst().continuation.resume(returning: true)
            } else {
                break
            }
        }
    }
}

// MARK: - Thumbnail cache bookkeeping

/// Delegate that counts what the thumbnail cache holds (NSCache does not expose it).
final class ThumbCacheStats: NSObject, NSCacheDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var inserted = 0
    private var evicted = 0
    private var bytesInserted = 0
    private var bytesEvicted = 0

    static func makeCache() -> NSCache<NSString, CGImage> {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 600
        cache.totalCostLimit = ProcessInfo.processInfo.physicalMemory >= (6 << 30) ? 128 << 20 : 64 << 20
        return cache
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // `as? CGImage` always succeeds for CF types, so check the type id instead.
        let ref = obj as CFTypeRef
        guard CFGetTypeID(ref) == CGImage.typeID else { return }
        let image = ref as! CGImage
        lock.lock()
        evicted += 1
        bytesEvicted += image.width * image.height * 4
        lock.unlock()
    }

    var summary: (entries: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (max(0, inserted - evicted), max(0, bytesInserted - bytesEvicted))
    }

    func noteInserted(bytes: Int) {
        lock.lock()
        inserted += 1
        bytesInserted += bytes
        lock.unlock()
    }

    func reset() {
        lock.lock()
        inserted = 0; evicted = 0; bytesInserted = 0; bytesEvicted = 0
        lock.unlock()
    }
}

// MARK: - Memory pressure and diagnostics

private let memoryLog = Logger(subsystem: "ca.hologram.lightcraft", category: "memory")

extension LibraryModel {
    /// Called once from `init`: purge on memory warnings; log memory every 30 s with `-LightCraftMemLog`.
    func startMemoryObservers() {
        memoryObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard let self else { return }
                self.purgeCaches(reason: "memory warning")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-LightCraftMemLog") {
            memoryLog.notice("memory log on: every 30 s; resident \(Self.residentBytes() >> 20) MB")
            memoryLogTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled, let self else { return }
                    self.logMemory()
                }
            }
        }
    }

    /// Empties the Swift caches, PhotoKit's thumbnail cache and the engine's caches.
    /// `renderGenerations` is bookkeeping for superseded renders and is deliberately kept.
    func purgeCaches(reason: String) {
        thumbCache.removeAllObjects()
        thumbStats.reset()
        photos.trimCaches()
        handle.trimMemory()
        memoryLog.notice("purge (\(reason, privacy: .public)); resident \(Self.residentBytes() >> 20) MB")
    }

    func logMemory() {
        let thumbs = thumbStats.summary
        let e = handle.memoryStats()
        memoryLog.notice("resident=\(Self.residentBytes() >> 20)MB thumbCache=\(thumbs.entries) entries \(thumbs.bytes >> 20)MB visible=\(self.visible.count) gens=\(self.renderGenerations.count) engine: budget=\(e.budget) cacheBudget=\(e.cacheBudget) cacheBytes=\(e.cacheBytes) renderedEntries=\(e.renderedEntries) renderedBytes=\(e.renderedBytes) thumbSrc=\(e.thumbSourceBytes) previewSrc=\(e.previewSourceBytes) fullSrc=\(e.fullSourceBytes) work=\(e.workBytes)/\(e.workLimit) gpuAlloc=\(e.gpuAllocated) gpuPooled=\(e.gpuPooled)")
    }

    nonisolated static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}
