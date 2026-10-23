import SwiftUI
@preconcurrency import LightCraftKit

/// Canvas tool operations: crop, masks, brush, white balance picker. Points are normalized image coordinates
/// (0...1, origin top-left), as the engine expects, so previews and exports match at any resolution.
extension LibraryModel {
    /// JSON form of a point.
    private static func pair(_ p: CGPoint) -> [Double] { [Double(p.x), Double(p.y)] }

    // MARK: Crop

    /// The active photo's crop rectangle (normalized, straightened frame) and straighten angle in degrees.
    func cropGeometry() -> (rect: CGRect, angle: Double) {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let id = state.active, let json = try? handle.developJson(id: id),
              let object = Self.decodeObject(json),
              let crop = object["crop"] as? [String: Any],
              let geometry = crop["geometry"] as? [String: Any] else { return (full, 0) }
        let angle = (geometry["angle"] as? NSNumber)?.doubleValue ?? 0
        guard let rect = geometry["rect"] as? [String: Any],
              let x0 = (rect["x0"] as? NSNumber)?.doubleValue, let y0 = (rect["y0"] as? NSNumber)?.doubleValue,
              let x1 = (rect["x1"] as? NSNumber)?.doubleValue, let y1 = (rect["y1"] as? NSNumber)?.doubleValue else {
            return (full, angle)
        }
        return (CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0)), angle)
    }

    /// `crop.set {rect: [x0,y0,x1,y1]}`. The engine rejects slivers; the error is reported, the crop stays.
    @discardableResult
    func setCrop(_ rect: CGRect) -> Bool {
        let r = rect.standardized
        return run("crop.set", ["rect": [Double(r.minX), Double(r.minY), Double(r.maxX), Double(r.maxY)]])
    }

    // MARK: Masks

    /// Linear gradient mask from `start` (full effect) to `end` (none).
    func addLinearMask(start: CGPoint, end: CGPoint) {
        guard hypot(end.x - start.x, end.y - start.y) > 0.01 else { return }
        if run("mask.add", ["kind": "linear", "start": Self.pair(start), "end": Self.pair(end)]) {
            activePanel = .masking
            activeTool = nil
        }
    }

    /// Radial gradient mask filling the box dragged from `a` to `b`.
    func addRadialMask(from a: CGPoint, to b: CGPoint) {
        let rx = abs(b.x - a.x) / 2, ry = abs(b.y - a.y) / 2
        guard rx > 0.01, ry > 0.01 else { return }
        let center = [Double((a.x + b.x) / 2), Double((a.y + b.y) / 2)]
        if run("mask.add", ["kind": "radial", "center": center, "rx": Double(rx), "ry": Double(ry)]) {
            activePanel = .masking
            activeTool = nil
        }
    }

    /// One brush stroke (all points of the finished drag) as a single command. The first stroke after
    /// choosing the Brush tool starts a new mask (id 0 matches no mask); later strokes continue it.
    func addBrushStroke(points: [CGPoint]) {
        guard !points.isEmpty else { return }
        var params: [String: Any] = [
            "points": points.map { Self.pair($0) },
            "size": brushSize,
            "feather": brushFeather,
            "erase": brushErase,
            "id": Int(brushMaskID ?? 0),
        ]
        if points.count == 1, let first = points.first { params["points"] = [Self.pair(first), Self.pair(first)] }
        if run("mask.brushStroke", params), let active = state.activeMask { brushMaskID = active }
    }

    // MARK: White balance

    /// White Balance Selector: `develop.wbPick` at a normalized point of the photo.
    func pickWhiteBalance(at point: CGPoint) {
        let x = min(max(point.x, 0), 1), y = min(max(point.y, 0), 1)
        if run("develop.wbPick", ["x": Double(x), "y": Double(y)]) { activeTool = nil }
    }
}
