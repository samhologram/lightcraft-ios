import SwiftUI

/// Drawing surface for the canvas tools, shown over the loupe while a tool is active:
/// - Linear Gradient: drag from the full-effect side to the no-effect side -> `mask.add {kind: linear}`.
/// - Radial Gradient: drag a box -> `mask.add {kind: radial}` (center, rx, ry).
/// - Brush: paint; the whole stroke is sent as one `mask.brushStroke` when the finger lifts.
/// - White Balance Selector: tap a neutral point -> `develop.wbPick`.
/// Points are normalized image coordinates (0...1), so the result is resolution independent.
struct MaskOverlay: View {
    let model: LibraryModel
    /// Size of the displayed photo in points.
    let size: CGSize

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var stroke: [CGPoint] = []

    private static let maxStrokePoints = 600

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            preview.allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .gesture(drawGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.activeTool?.title ?? "Tool")
        .accessibilityIdentifier("toolOverlay.\(model.activeTool?.rawValue ?? "none")")
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        switch model.activeTool {
        case .linear:
            if let start, let current {
                Path { p in
                    p.move(to: start)
                    p.addLine(to: current)
                }
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                Circle().fill(Color.yellow).frame(width: 10, height: 10).position(start)
                Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 10, height: 10).position(current)
            }
        case .radial:
            if let start, let current {
                let box = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                                 width: abs(current.x - start.x), height: abs(current.y - start.y))
                Ellipse().stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
            }
        case .brush:
            if stroke.count > 0 {
                Path { p in
                    guard let first = stroke.first else { return }
                    p.move(to: first)
                    for point in stroke.dropFirst() { p.addLine(to: point) }
                    if stroke.count == 1 { p.addLine(to: first) }
                }
                .stroke(
                    (model.brushErase ? Color.red : Color.cyan).opacity(0.45),
                    style: StrokeStyle(lineWidth: max(2, model.brushSize * max(size.width, size.height)),
                                       lineCap: .round, lineJoin: .round))
            }
        default:
            EmptyView()
        }
    }

    // MARK: Gesture

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if start == nil { start = value.startLocation }
                current = value.location
                if model.activeTool == .brush {
                    if let last = stroke.last, hypot(value.location.x - last.x, value.location.y - last.y) < 1.5 { return }
                    stroke.append(value.location)
                }
            }
            .onEnded { value in
                let begin = start ?? value.startLocation
                let end = value.location
                defer { start = nil; current = nil; stroke = [] }
                switch model.activeTool {
                case .linear:
                    model.addLinearMask(start: normalized(begin), end: normalized(end))
                case .radial:
                    model.addRadialMask(from: normalized(begin), to: normalized(end))
                case .brush:
                    let points = thinned(stroke.isEmpty ? [end] : stroke).map(normalized)
                    model.addBrushStroke(points: points)
                case .wbPicker:
                    model.pickWhiteBalance(at: normalized(end))
                default:
                    break
                }
            }
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: min(max(point.x / size.width, 0), 1), y: min(max(point.y / size.height, 0), 1))
    }

    /// Keeps a long stroke under the command's point budget, always including the last point.
    private func thinned(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > Self.maxStrokePoints else { return points }
        let step = Double(points.count - 1) / Double(Self.maxStrokePoints - 1)
        var out: [CGPoint] = []
        for i in 0..<Self.maxStrokePoints {
            out.append(points[min(points.count - 1, Int((Double(i) * step).rounded()))])
        }
        return out
    }
}
