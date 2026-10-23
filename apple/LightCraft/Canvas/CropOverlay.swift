import SwiftUI

/// Crop frame with rule-of-thirds guides, shown over the loupe while the Crop & Rotate panel is open.
/// Dragging a corner, an edge or the inside of the frame edits a local rectangle; lifting the finger sends one
/// `crop.set {rect}` (one undo step). The engine clamps and constrains the rectangle (aspect lock, image
/// bounds), and the overlay then re-reads the stored crop.
///
/// The rectangle is normalized in the straightened frame, drawn over the displayed photo.
struct CropOverlay: View {
    let model: LibraryModel
    /// Size of the displayed photo in points.
    let size: CGSize

    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var handle: Handle?
    @State private var startRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var dragging = false

    private enum Handle { case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, move }

    private static let slop: CGFloat = 30
    private static let minSide: CGFloat = 0.05

    var body: some View {
        ZStack {
            dimming
            Path { p in
                p.addRect(cropFrame)
            }
            // Kept: crop guides over photo content.
            .stroke(Color.white, lineWidth: 1.5)
            thirds
            corners
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .task(id: model.state.revision) {
            if !dragging { rect = model.cropGeometry().rect }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop frame")
        .accessibilityIdentifier("cropOverlay")
    }

    /// The crop rectangle in points.
    private var cropFrame: CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    private var dimming: some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            p.addRect(cropFrame)
        }
        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private var thirds: some View {
        Path { p in
            let f = cropFrame
            for i in 1...2 {
                let t = CGFloat(i) / 3
                p.move(to: CGPoint(x: f.minX + f.width * t, y: f.minY))
                p.addLine(to: CGPoint(x: f.minX + f.width * t, y: f.maxY))
                p.move(to: CGPoint(x: f.minX, y: f.minY + f.height * t))
                p.addLine(to: CGPoint(x: f.maxX, y: f.minY + f.height * t))
            }
        }
        .stroke(Color.white.opacity(0.55), lineWidth: 0.75)
        .allowsHitTesting(false)
    }

    /// L-shaped grips at the four corners.
    private var corners: some View {
        Path { p in
            let f = cropFrame
            let len = min(22, f.width / 3, f.height / 3)
            p.move(to: CGPoint(x: f.minX, y: f.minY + len)); p.addLine(to: CGPoint(x: f.minX, y: f.minY)); p.addLine(to: CGPoint(x: f.minX + len, y: f.minY))
            p.move(to: CGPoint(x: f.maxX - len, y: f.minY)); p.addLine(to: CGPoint(x: f.maxX, y: f.minY)); p.addLine(to: CGPoint(x: f.maxX, y: f.minY + len))
            p.move(to: CGPoint(x: f.maxX, y: f.maxY - len)); p.addLine(to: CGPoint(x: f.maxX, y: f.maxY)); p.addLine(to: CGPoint(x: f.maxX - len, y: f.maxY))
            p.move(to: CGPoint(x: f.minX + len, y: f.maxY)); p.addLine(to: CGPoint(x: f.minX, y: f.maxY)); p.addLine(to: CGPoint(x: f.minX, y: f.maxY - len))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
    }

    // MARK: Dragging

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                if handle == nil, !dragging {
                    handle = hit(value.startLocation)
                    startRect = rect
                    dragging = handle != nil
                }
                guard let handle else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                rect = Self.resized(startRect, handle: handle, dx: dx, dy: dy)
            }
            .onEnded { _ in
                defer { handle = nil; dragging = false }
                guard dragging else { return }
                if rect != startRect { model.setCrop(rect) }
                rect = model.cropGeometry().rect
            }
    }

    private func hit(_ point: CGPoint) -> Handle? {
        let f = cropFrame
        let nearLeft = abs(point.x - f.minX) < Self.slop, nearRight = abs(point.x - f.maxX) < Self.slop
        let nearTop = abs(point.y - f.minY) < Self.slop, nearBottom = abs(point.y - f.maxY) < Self.slop
        let withinX = point.x > f.minX - Self.slop && point.x < f.maxX + Self.slop
        let withinY = point.y > f.minY - Self.slop && point.y < f.maxY + Self.slop
        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }
        if nearTop && withinX { return .top }
        if nearBottom && withinX { return .bottom }
        if nearLeft && withinY { return .left }
        if nearRight && withinY { return .right }
        return f.contains(point) ? .move : nil
    }

    private static func resized(_ start: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x0 = start.minX, y0 = start.minY, x1 = start.maxX, y1 = start.maxY
        func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        switch handle {
        case .move:
            let w = start.width, h = start.height
            x0 = min(max(start.minX + dx, 0), 1 - w); y0 = min(max(start.minY + dy, 0), 1 - h)
            x1 = x0 + w; y1 = y0 + h
        case .topLeft: x0 = clamp(x0 + dx); y0 = clamp(y0 + dy)
        case .topRight: x1 = clamp(x1 + dx); y0 = clamp(y0 + dy)
        case .bottomLeft: x0 = clamp(x0 + dx); y1 = clamp(y1 + dy)
        case .bottomRight: x1 = clamp(x1 + dx); y1 = clamp(y1 + dy)
        case .top: y0 = clamp(y0 + dy)
        case .bottom: y1 = clamp(y1 + dy)
        case .left: x0 = clamp(x0 + dx)
        case .right: x1 = clamp(x1 + dx)
        }
        // Keep a minimum size by holding the dragged edge off the opposite one.
        if x1 - x0 < minSide { if [.left, .topLeft, .bottomLeft].contains(handle) { x0 = x1 - minSide } else { x1 = x0 + minSide } }
        if y1 - y0 < minSide { if [.top, .topLeft, .topRight].contains(handle) { y0 = y1 - minSide } else { y1 = y0 + minSide } }
        return CGRect(x: x0, y: y0, width: max(x1 - x0, minSide), height: max(y1 - y0, minSide))
    }
}
