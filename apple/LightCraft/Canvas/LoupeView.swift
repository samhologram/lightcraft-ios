import SwiftUI
@preconcurrency import LightCraftKit

/// The active photo, rendered by the engine at the view's pixel size (times the zoom), with pinch zoom,
/// pan, double-tap fit / 100 %, and press-and-hold to see the original (Before).
///
/// Zoom model: `model.zoomScale` is relative to fit. The image is rendered at `fit size * zoom` pixels (capped
/// at 4096 px) and shown in a fit-sized frame that is scaled, so it stays sharp when zoomed. While a slider
/// or overlay drag is open the render is a draft; the full-quality render follows when the drag ends.
struct LoupeView: View {
    let model: LibraryModel

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var renderedID: UInt64?
    @State private var baseOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var holding = false

    private static let maxRenderEdge: CGFloat = 4096
    private static let maxZoom: Double = 16

    /// Everything that invalidates the rendered picture.
    private struct RenderKey: Hashable {
        let photo: UInt64?
        let revision: UInt64
        let width: Int
        let height: Int
        let before: Bool
        let applyCrop: Bool
        let draft: Bool
        let tick: Int
    }

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedSize(in: geo.size)
            let scale = liveScale
            let offset = clamped(
                CGSize(width: baseOffset.width + dragTranslation.width, height: baseOffset.height + dragTranslation.height),
                fitted: fitted, scale: scale, viewport: geo.size)
            ZStack {
                Color.clear
                if let image {
                    ZStack {
                        Image(decorative: image, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitted.width, height: fitted.height)
                        overlay(size: fitted)
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(scale)
                    .offset(offset)
                } else if model.activePhoto != nil {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .gesture(panGesture(fitted: fitted, viewport: geo.size), including: overlayActive ? .subviews : .all)
            .simultaneousGesture(magnify(viewport: geo.size, fitted: fitted))
            .simultaneousGesture(holdGesture, including: overlayActive ? .subviews : .all)
            .onTapGesture(count: 2) { if !overlayActive { model.runUI("view.zoomToggle") } }
            .onChange(of: holding) { _, now in model.showOriginal = now }
            .onChange(of: model.zoomToFit) { _, fit in if fit { baseOffset = .zero } }
            .onChange(of: model.activePhoto?.id) { _, _ in baseOffset = .zero }
            .task(id: renderKey(viewport: geo.size)) { await renderImage(viewport: geo.size) }
        }
        .background(Color.black.opacity(0.0001))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loupe")
    }

    // MARK: Overlays

    private var overlayActive: Bool {
        model.activeTool != nil || model.activePanel == .crop
    }

    @ViewBuilder
    private func overlay(size: CGSize) -> some View {
        if model.activeTool == .linear || model.activeTool == .radial || model.activeTool == .brush
            || model.activeTool == .wbPicker {
            MaskOverlay(model: model, size: size)
        } else if model.activePanel == .crop {
            CropOverlay(model: model, size: size)
        }
    }

    // MARK: Geometry

    private var liveScale: CGFloat {
        CGFloat(min(Self.maxZoom, max(0.5, model.zoomScale * Double(pinch))))
    }

    /// Breathing room around the photo at fit, so it never touches the bars, the filmstrip or the panel switcher.
    private static let fitMargin: CGFloat = 8

    /// The photo's aspect fitted into the viewport (less a small margin).
    private func fittedSize(in viewport: CGSize) -> CGSize {
        var aspect: CGFloat = 1.5
        if let image, image.height > 0 {
            aspect = CGFloat(image.width) / CGFloat(image.height)
        } else if let info = model.activePhoto, info.height > 0 {
            aspect = CGFloat(info.width) / CGFloat(info.height)
        }
        let box = CGSize(width: viewport.width - 2 * Self.fitMargin, height: viewport.height - 2 * Self.fitMargin)
        guard box.width > 0, box.height > 0 else { return .zero }
        let width = min(box.width, box.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    /// Keeps the zoomed picture covering the viewport (no panning into empty space).
    private func clamped(_ offset: CGSize, fitted: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let maxX = max(0, (fitted.width * scale - viewport.width) / 2)
        let maxY = max(0, (fitted.height * scale - viewport.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    // MARK: Gestures

    private func panGesture(fitted: CGSize, viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, state, _ in
                if model.zoomScale > 1.001 { state = value.translation }
            }
            .onEnded { value in
                guard model.zoomScale > 1.001 else { return }
                let moved = CGSize(width: baseOffset.width + value.translation.width,
                                   height: baseOffset.height + value.translation.height)
                baseOffset = clamped(moved, fitted: fitted, scale: CGFloat(model.zoomScale), viewport: viewport)
            }
    }

    private func magnify(viewport: CGSize, fitted: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                let zoom = model.zoomScale * Double(value.magnification)
                if zoom <= 1.05 {
                    model.runUI("view.zoomFit")
                    baseOffset = .zero
                } else {
                    model.zoomToFit = false
                    model.zoomScale = min(Self.maxZoom, zoom)
                    baseOffset = clamped(baseOffset, fitted: fitted, scale: CGFloat(model.zoomScale), viewport: viewport)
                }
            }
    }

    /// Press and hold shows the original; releasing returns to the edit.
    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
    }

    // MARK: Rendering

    /// Pixel box the engine fits the photo into: the viewport in pixels times the zoom, capped.
    private func renderBox(viewport: CGSize) -> CGSize {
        let zoom = CGFloat(max(1, model.zoomScale))
        let w = viewport.width * displayScale * zoom
        let h = viewport.height * displayScale * zoom
        let longest = max(w, h, 1)
        let cap = min(1, Self.maxRenderEdge / longest)
        return CGSize(width: (w * cap).rounded(), height: (h * cap).rounded())
    }

    private func renderKey(viewport: CGSize) -> RenderKey {
        let box = renderBox(viewport: viewport)
        return RenderKey(
            photo: model.activePhoto?.id, revision: model.state.revision, width: Int(box.width), height: Int(box.height),
            before: model.showOriginal, applyCrop: !model.croppedFrame, draft: model.isDragging, tick: model.undoRedoTick)
    }

    private func renderImage(viewport: CGSize) async {
        guard let id = model.activePhoto?.id, viewport.width > 1, viewport.height > 1 else {
            image = nil
            renderedID = nil
            return
        }
        if renderedID != id {
            image = nil
            renderedID = id
        }
        let key = renderKey(viewport: viewport)
        // Coalesce bursts: a draft waits a frame, a full render waits a little longer (cancelled when superseded).
        try? await Task.sleep(for: .milliseconds(key.draft ? 12 : 60))
        guard !Task.isCancelled else { return }
        let box = renderBox(viewport: viewport)
        guard let rendered = await model.render(id, size: box, before: key.before, draft: key.draft, applyCrop: key.applyCrop),
              !Task.isCancelled else { return }
        image = rendered
        publishHundredPercent(rendered: rendered, viewport: viewport)
    }

    /// Zoom (relative to fit) at which one photo pixel is one screen pixel.
    private func publishHundredPercent(rendered: CGImage, viewport: CGSize) {
        guard let info = model.activePhoto else { return }
        let fitted = fittedSize(in: viewport)
        let fittedPixels = max(fitted.width, fitted.height) * displayScale
        guard fittedPixels > 0 else { return }
        let photoLongEdge = CGFloat(max(info.width, info.height))
        model.hundredPercentScale = max(1.5, min(Self.maxZoom, Double(photoLongEdge / fittedPixels)))
    }
}
