import SwiftUI
import Observation
@preconcurrency import LightCraftKit

/// Editor state of one open library: mirrors the engine (`LibraryHandle`) for SwiftUI, runs commands by id
/// and registers engine history on the scene's `UndoManager`.
@MainActor @Observable
final class LibraryModel {
    /// The thread-safe engine object. Background work (rendering, thumbnails, import) calls it directly.
    @ObservationIgnored var handle: LibraryHandle

    // MARK: Engine mirror (refreshed after every call)
    var state: LibraryState
    var visible: [UInt64] = []
    var albums: [AlbumInfo] = []
    var activePhoto: PhotoInfo?
    /// Develop controls of the active photo, keyed by control id ("light.exposure").
    var developValues: [String: Double] = [:]

    // MARK: UI state shared by Core and UI
    var activePanel: Panel = AppSettings.lastPanel {
        didSet {
            AppSettings.lastPanel = activePanel
            if !panelRevealSuppressed { revealPanelInLayout(activePanel) }  // any way of opening a panel shows it
            if activePanel != oldValue { refreshLight() }  // keeps `croppedFrame` current
        }
    }
    /// The iPad inspector column's arrangement (order, visible, collapsed); persisted.
    var panelLayout: PanelLayout = AppSettings.panelLayout {
        didSet { AppSettings.panelLayout = panelLayout }
    }
    /// Bumps when a panel is opened so the inspector column scrolls to it; `panelRevealTarget` says which.
    var panelRevealTick = 0
    var panelRevealTarget: Panel?
    @ObservationIgnored var panelRevealSuppressed = false
    var activeTool: Tool?
    var mode: Mode = .grid {
        didSet {
            if oldValue == .loupe && mode != .loupe { commitEdits() }
            if mode != .loupe { canvasOnly = false }
        }
    }
    /// Full-screen canvas: only the photo is shown (no panels, sidebar, bars). UI-only; the loupe resets it.
    var canvasOnly = false
    /// Shown as an alert with the full message.
    var lastError: String?
    /// A one-off informational message (alert), e.g. the preset import summary.
    var lastNotice: String?
    /// Bumps after a preset import so the Presets panel reloads.
    var presetImportTick = 0
    var isDemoReady = false
    /// The editor stays closed until catalog paths have been rebased after an app-container move.
    var isCatalogReady = false
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Set for a command that takes parameters; the UI shows a `CommandSheet`.
    var pendingCommand: String?
    var showCommandPalette = false
    /// Press-and-hold Before.
    var showOriginal = false
    /// Presents the preset / profile importer (`file.importPresets`).
    var showPresetImporter = false
    /// Demo samples (engine demo photos) instead of the Photos library; edits are not written back.
    var samplesMode = false
    /// The Photos asset (local identifier, index in the source) open in the loupe.
    var openLocalID: String?
    var openIndex: Int?
    var isOpening = false
    /// Develop settings JSON of the open photo when it was opened or last written back.
    @ObservationIgnored var baselineJSON: String?
    @ObservationIgnored var writeTask: Task<Void, Never>?
    /// Write-backs to Photos in flight, and how many finished (for the saving indicator and tests).
    var writeBackCount = 0
    var savedCount = 0
    var showExport = false
    /// HDR editing is on for the active photo (`develop.hdr`): the HDR-only controls show.
    var hdrEnabled = false
    /// The active photo is edited as black and white (treatment B&W or a mono profile): the B&W mixer replaces the colour mixer.
    var isBlackAndWhite = false
    var inspectorVisible: Bool { didSet { AppSettings.inspectorVisible = inspectorVisible } }
    /// Loupe fit (true) vs `zoomScale`.
    var zoomToFit = true
    /// Loupe zoom relative to fit (1 = fit). The loupe renders at the zoomed size.
    var zoomScale: Double = 1
    /// Zoom that shows one image pixel per screen pixel; published by the loupe for `view.zoom100`.
    var hundredPercentScale: Double = 2
    /// Grid cell edge in points.
    var thumbSize: Double { didSet { AppSettings.thumbSize = thumbSize } }
    /// Bumps on undo/redo so views re-render.
    var undoRedoTick = 0
    /// True while a slider or overlay drag is open (draft-quality renders).
    private(set) var isDragging = false
    /// Per-photo counter that bumps when a command may have changed the photo; keys the thumbnail cache.
    private(set) var thumbnailVersions: [UInt64: Int] = [:]
    /// True while the Crop panel is open on a photo that already has a crop or angle: the loupe then shows the
    /// uncropped frame (the engine's Before render), so the crop overlay and the picture share one frame.
    var croppedFrame = false
    /// Mask the brush tool paints into (nil: the next stroke starts a new brush mask).
    var brushMaskID: UInt32?
    /// Brush tool settings, as fractions (size of the long edge) and percent.
    var brushSize: Double = 0.04
    var brushFeather: Double = 50
    var brushErase = false

    // MARK: Internals shared with the extensions
    @ObservationIgnored var dragHistoryStart: UInt64 = 0
    /// Rendered thumbnails. Bounded by count and by decoded bytes (cost = width * height * 4).
    @ObservationIgnored let thumbStats = ThumbCacheStats()
    @ObservationIgnored let thumbCache: NSCache<NSString, CGImage> = ThumbCacheStats.makeCache()
    /// Limits concurrent engine renders (loupe renders have their own lane; grid thumbnails use at most two) and lets a newer render of the same view supersede queued ones.
    @ObservationIgnored let renderGate = AsyncGate(limit: 3, backgroundLimit: 2)
    @ObservationIgnored var renderGenerations: [String: Int] = [:]
    @ObservationIgnored var memoryObserver: Task<Void, Never>?
    @ObservationIgnored var memoryLogTask: Task<Void, Never>?

    init(handle: LibraryHandle) {
        AppSettings.registerDefaults()
        self.handle = handle
        state = handle.state()
        inspectorVisible = AppSettings.initialInspectorVisible
        thumbSize = AppSettings.thumbSize
        thumbCache.delegate = thumbStats
        refresh()
        startMemoryObservers()
    }

    deinit {
        memoryObserver?.cancel()
        memoryLogTask?.cancel()
    }

    // MARK: Refresh

    /// Re-reads everything the UI shows. Call after every engine call.
    func refresh() {
        state = handle.state()
        let ids = handle.visiblePhotos()
        if ids != visible { visible = ids }
        albums = handle.albums()
        refreshActive()
    }

    /// Cheaper refresh for slider drags: state, active photo and its values (no visible list / albums).
    func refreshLight() {
        state = handle.state()
        refreshActive()
    }

    private func refreshActive() {
        let cropOpen = activePanel == .crop
        defer {
            if cropOpen, state.active != nil {
                let crop = cropGeometry()
                let full = CGRect(x: 0, y: 0, width: 1, height: 1)
                let cropped = crop.rect.standardized != full || abs(crop.angle) > 0.0001
                if cropped != croppedFrame { croppedFrame = cropped }
            } else if croppedFrame {
                croppedFrame = false
            }
        }
        guard let id = state.active else {
            activePhoto = nil
            if !developValues.isEmpty { developValues = [:] }
            hdrEnabled = false
            isBlackAndWhite = false
            return
        }
        activePhoto = handle.photoInfo(id: id)
        let values = Self.decodeValues(try? handle.developValues(id: id))
        if values != developValues { developValues = values }
        // Same rule as the desktop's `is_bw` and `d.hdr.enabled`.
        let flags = Self.decodeFlags(try? handle.developJson(id: id))
        if flags.hdr != hdrEnabled { hdrEnabled = flags.hdr }
        if flags.bw != isBlackAndWhite { isBlackAndWhite = flags.bw }
    }

    private static func decodeFlags(_ json: String?) -> (hdr: Bool, bw: Bool) {
        guard let json, let data = json.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (false, false) }
        let hdr = (d["hdr"] as? [String: Any])?["enabled"] as? Bool ?? false
        let profile = (d["profile"] as? [String: Any])?["id"] as? String ?? ""
        let bw = d["treatment"] as? String == "bw" || profile == "lc.mono" || profile.hasPrefix("lc.bw.")
        return (hdr, bw)
    }

    private static func decodeValues(_ json: String?) -> [String: Double] {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    // MARK: Running commands

    /// Executes an engine command and returns its result JSON object; errors go to `lastError`.
    /// Refreshes the mirror and registers undo. Use `run` unless the result is needed.
    @discardableResult
    func execute(_ id: String, _ params: [String: Any] = [:]) -> [String: Any]? {
        guard isCatalogReady || samplesMode else {
            lastError = "The photo library is still restoring its cached originals."
            return nil
        }
        guard let json = Self.encode(params) else {
            lastError = "Could not encode the parameters of \(id)."
            return nil
        }
        let historyBefore = state.historyId
        let result: String
        do {
            result = try handle.execute(id: id, paramsJson: json)
        } catch {
            lastError = error.localizedDescription
            refresh()
            return nil
        }
        finishMutation(id: id, params: params, historyBefore: historyBefore)
        return Self.decodeObject(result) ?? [:]
    }

    /// Runs an engine command (or a UI-only / undo id) by id. Returns false when it failed.
    @discardableResult
    func run(_ id: String, _ params: [String: Any] = [:]) -> Bool {
        switch id {
        case "edit.undo": undo(); return true
        case "edit.redo": redo(); return true
        case "library.next" where !samplesMode: stepPhoto(1); return true
        case "library.previous" where !samplesMode: stepPhoto(-1); return true
        default: break
        }
        if CommandCatalog.shared.isUI(id) {
            runUI(id)
            return true
        }
        return execute(id, params) != nil
    }

    /// After an engine call: refresh, drop stale thumbnails, and mirror a new history step on the UndoManager.
    func finishMutation(id: String, params: [String: Any], historyBefore: UInt64) {
        refresh()
        guard !CommandCatalog.shared.isQuery(id) else { return }
        invalidateThumbnails(params: params)
        if state.historyId != historyBefore { registerUndoStep(label: state.undoLabel) }
    }

    /// Photos a command may have changed: the active one, the selection and explicit `ids`.
    private func invalidateThumbnails(params: [String: Any]) {
        var ids = Set(state.selected)
        if let active = state.active { ids.insert(active) }
        if let explicit = params["ids"] as? [Any] {
            for value in explicit { if let n = (value as? NSNumber)?.uint64Value { ids.insert(n) } }
        }
        for id in ids { thumbnailVersions[id, default: 0] += 1 }
    }

    func select(_ id: UInt64) {
        run("library.select", ["ids": [id], "active": id])
    }

    /// Selects the photo and shows it in the loupe.
    func open(_ id: UInt64) {
        select(id)
        mode = .loupe
    }

    // MARK: Interactive edits (slider drags)

    /// Sets one develop control. During a drag (`beginDrag`) this is a cheap engine call with no undo
    /// registration; outside a drag it is a normal undoable command.
    func setDevelop(_ control: String, _ value: Double) {
        guard isDragging else {
            run("develop.set", ["values": [control: value]])
            return
        }
        guard let json = Self.encode(["values": [control: value]]) else { return }
        do {
            _ = try handle.execute(id: "develop.set", paramsJson: json)
        } catch {
            lastError = error.localizedDescription
        }
        developValues[control] = value
        refreshLight()
    }

    /// Opens an interaction: every edit until `endDrag` is one undo step.
    func beginDrag(_ label: String) {
        guard !isDragging else { return }
        dragHistoryStart = handle.state().historyId
        do {
            try handle.beginInteraction(label: label)
            isDragging = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        do {
            try handle.endInteraction()
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if let active = state.active { thumbnailVersions[active, default: 0] += 1 }
        if state.historyId != dragHistoryStart { registerUndoStep(label: state.undoLabel) }
    }

    // MARK: JSON

    nonisolated static func encode(_ params: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(params),
              let data = try? JSONSerialization.data(withJSONObject: params),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    nonisolated static func decodeObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
