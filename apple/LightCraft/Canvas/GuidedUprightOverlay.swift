import SwiftUI
@preconcurrency import LightCraftKit

/// One Guided Upright guide: two endpoints in normalized image coordinates (0...1, origin top-left).
struct UprightGuide: Equatable, Sendable {
    var a: CGPoint
    var b: CGPoint

    var array: [Double] { [Double(a.x), Double(a.y), Double(b.x), Double(b.y)] }
}

extension LibraryModel {
    /// The active photo's Guided Upright guides (`geometry.guides` in the develop JSON).
    func uprightGuides() -> [UprightGuide] {
        guard let id = state.active, let json = try? handle.developJson(id: id),
              let object = Self.decodeObject(json),
              let geometry = object["geometry"] as? [String: Any],
              let raw = geometry["guides"] as? [Any] else { return [] }
        func point(_ any: Any?) -> CGPoint? {
            if let d = any as? [String: Any], let x = (d["x"] as? NSNumber)?.doubleValue,
               let y = (d["y"] as? NSNumber)?.doubleValue { return CGPoint(x: x, y: y) }
            if let a = any as? [Any], a.count == 2, let x = (a[0] as? NSNumber)?.doubleValue,
               let y = (a[1] as? NSNumber)?.doubleValue { return CGPoint(x: x, y: y) }
            return nil
        }
        return raw.compactMap { item in
            guard let pair = item as? [Any], pair.count == 2, let a = point(pair[0]), let b = point(pair[1]) else { return nil }
            return UprightGuide(a: a, b: b)
        }
    }

    /// `geometry.guides {guides: [[x0,y0,x1,y1], ...], add?}`: replaces the guides, or appends one with `add`
    /// (the engine keeps at most four, dropping the oldest, and switches Upright to Guided).
    @discardableResult
    func setUprightGuides(_ guides: [UprightGuide], add: Bool = false) -> Bool {
        var params: [String: Any] = ["guides": guides.map(\.array)]
        if add { params["add"] = true }
        return run("geometry.guides", params)
    }
}

/// Guided Upright: draw up to four guides along lines that should be vertical or horizontal by dragging on the
/// photo (touch, Pencil or pointer). Endpoints are draggable handles with a 44 pt hit area; a long press on a
/// guide offers Delete. Each change is one `geometry.guides` command (one undo step).
///
/// Guides are normalized, so they are resolution independent. The engine stores them in the lens-corrected frame;
/// the photo is shown in the transformed frame, so points are mapped stored -> displayed for drawing and
/// displayed -> stored before they are committed (identity if the bridge call fails).
struct GuidedUprightOverlay: View {
    let model: LibraryModel
    /// Size of the displayed photo in points.
    let size: CGSize
    /// False while zoomed in: the empty photo area then passes drags through so the photo can be panned
    /// (handles stay draggable). Drawing a new guide needs the fit zoom.
    var drawEnabled = true
    /// Set while a guide is being drawn or a handle dragged.
    @Binding var interacting: Bool

    /// Guides as stored by the engine (lens-corrected frame).
    @State private var guides: [UprightGuide] = []
    /// The same guides in the displayed frame.
    @State private var display: [UprightGuide] = []
    /// The guide being drawn (displayed frame).
    @State private var drawing: UprightGuide?
    /// The endpoint being dragged (guide index, 0 = start, 1 = end) and its working copy of the displayed guides.
    @State private var dragging: (index: Int, end: Int)?
    @State private var working: [UprightGuide]?

    private static let space = "guidedUprightOverlay"
    private static let handleHit: CGFloat = 44
    /// Minimum guide length in points.
    private static let minLengthPoints: CGFloat = 4
    /// A drag starting this close (points) to an existing guide belongs to that guide (long-press menu), not a new one.
    private static let guideSlop: CGFloat = 22
    private static let nudgeStep: CGFloat = 0.02
    private static let amber = Color(red: 1, green: 0.77, blue: 0.16)

    private struct ReloadKey: Hashable {
        let photo: String
        let revision: String
    }

    private var reloadKey: ReloadKey {
        ReloadKey(photo: String(describing: model.state.active), revision: String(describing: model.state.revision))
    }

    private var shown: [UprightGuide] { working ?? display }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .allowsHitTesting(drawEnabled)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, guide in
                guideView(index: index, guide: guide)
            }
            if let drawing {
                line(drawing, color: .white)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: Self.space)
        .onChange(of: model.state.active) { _, _ in
            drawing = nil
            dragging = nil
            working = nil
            reload()
        }
        .onChange(of: drawing != nil || dragging != nil) { _, now in interacting = now }
        .onDisappear { interacting = false }
        .task(id: reloadKey) { if dragging == nil { reload() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guided Upright")
        .accessibilityHint("Drag on the photo along a line that should be vertical or horizontal.")
        .accessibilityIdentifier("tool.guidedUpright.overlay")
    }

    // MARK: Model sync

    private func reload() {
        let stored = model.uprightGuides()
        guides = stored
        display = map(stored, toDisplay: true)
    }

    /// Maps guides between the stored and the displayed frame; identity when the bridge fails or returns nonsense.
    private func map(_ list: [UprightGuide], toDisplay: Bool) -> [UprightGuide] {
        guard !list.isEmpty, let id = model.state.active else { return list }
        let flat = list.flatMap(\.array)
        let out: [Double]?
        if toDisplay {
            out = try? model.handle.mapPointsToDisplay(id: id, points: flat)
        } else {
            out = try? model.handle.mapPointsFromDisplay(id: id, points: flat)
        }
        guard let out, out.count == flat.count, out.allSatisfy(\.isFinite) else { return list }
        return list.indices.map { i in
            UprightGuide(a: CGPoint(x: out[4 * i], y: out[4 * i + 1]), b: CGPoint(x: out[4 * i + 2], y: out[4 * i + 3]))
        }
    }

    /// Commits displayed guides (replacing all); reloads from the engine if it refuses.
    private func commit(_ updated: [UprightGuide]) {
        let stored = map(updated, toDisplay: false)
        if model.setUprightGuides(stored) {
            guides = stored
            display = updated
        } else {
            reload()
        }
    }

    private func lengthInPoints(_ g: UprightGuide) -> CGFloat {
        hypot((g.b.x - g.a.x) * size.width, (g.b.y - g.a.y) * size.height)
    }

    // MARK: Drawing

    private func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

    private func norm(_ p: CGPoint) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }

    private func line(_ guide: UprightGuide, color: Color) -> some View {
        Path { p in
            p.move(to: px(guide.a))
            p.addLine(to: px(guide.b))
        }
        .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        .overlay {
            Path { p in
                p.move(to: px(guide.a))
                p.addLine(to: px(guide.b))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        }
    }

    private func guideView(index: Int, guide: UprightGuide) -> some View {
        ZStack {
            line(guide, color: Self.amber)
                .allowsHitTesting(false)
            // Wide, invisible target for the long-press menu (its touches fall through to the drawing gesture).
            Path { p in
                p.move(to: px(guide.a))
                p.addLine(to: px(guide.b))
            }
            .stroke(Color.clear, style: StrokeStyle(lineWidth: Self.handleHit, lineCap: .round))
            .contentShape(Path { p in
                p.move(to: px(guide.a))
                p.addLine(to: px(guide.b))
            }.strokedPath(StrokeStyle(lineWidth: Self.handleHit, lineCap: .round)))
            .contextMenu {
                Button(role: .destructive) { delete(index) } label: {
                    Label("Delete Guide", systemImage: "trash")
                }
            }
            handle(index: index, end: 0, at: guide.a)
            handle(index: index, end: 1, at: guide.b)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guide \(index + 1)")
        .accessibilityValue(guideValue(guide))
        .accessibilityIdentifier("control.guidedUpright.guide.\(index)")
        .accessibilityAction(named: "Delete Guide") { delete(index) }
        .accessibilityAction(named: "Move Start Left") { nudge(index, end: 0, dx: -Self.nudgeStep, dy: 0) }
        .accessibilityAction(named: "Move Start Right") { nudge(index, end: 0, dx: Self.nudgeStep, dy: 0) }
        .accessibilityAction(named: "Move Start Up") { nudge(index, end: 0, dx: 0, dy: -Self.nudgeStep) }
        .accessibilityAction(named: "Move Start Down") { nudge(index, end: 0, dx: 0, dy: Self.nudgeStep) }
        .accessibilityAction(named: "Move End Left") { nudge(index, end: 1, dx: -Self.nudgeStep, dy: 0) }
        .accessibilityAction(named: "Move End Right") { nudge(index, end: 1, dx: Self.nudgeStep, dy: 0) }
        .accessibilityAction(named: "Move End Up") { nudge(index, end: 1, dx: 0, dy: -Self.nudgeStep) }
        .accessibilityAction(named: "Move End Down") { nudge(index, end: 1, dx: 0, dy: Self.nudgeStep) }
    }

    private func guideValue(_ g: UprightGuide) -> String {
        let dx = abs(g.b.x - g.a.x) * size.width, dy = abs(g.b.y - g.a.y) * size.height
        return dy >= dx ? String(localized: "Vertical line") : String(localized: "Horizontal line")
    }

    private func handle(index: Int, end: Int, at point: CGPoint) -> some View {
        Circle()
            .fill(Self.amber)
            .overlay(Circle().stroke(Color.black, lineWidth: 1))
            .frame(width: 14, height: 14)
            .frame(width: Self.handleHit, height: Self.handleHit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if dragging == nil {
                            dragging = (index, end)
                            working = display
                        }
                        guard working?.indices.contains(index) == true else { return }
                        let p = norm(value.location)
                        if end == 0 { working?[index].a = p } else { working?[index].b = p }
                    }
                    .onEnded { _ in
                        defer { dragging = nil; working = nil }
                        guard let updated = working, updated.indices.contains(index), updated != display else { return }
                        guard lengthInPoints(updated[index]) > Self.minLengthPoints else { return }
                        commit(updated)
                    }
            )
            .position(px(point))
    }

    /// Distance in points from `p` to the segment of `g`.
    private func distance(from p: CGPoint, to g: UprightGuide) -> CGFloat {
        let a = px(g.a), b = px(g.b)
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func startsNearGuide(_ start: CGPoint) -> Bool {
        shown.contains { distance(from: start, to: $0) < Self.guideSlop }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drawing == nil, startsNearGuide(value.startLocation) { return }
                drawing = UprightGuide(a: norm(value.startLocation), b: norm(value.location))
            }
            .onEnded { value in
                defer { drawing = nil }
                guard drawing != nil, !startsNearGuide(value.startLocation) else { return }
                let guide = UprightGuide(a: norm(value.startLocation), b: norm(value.location))
                guard lengthInPoints(guide) > Self.minLengthPoints else { return }
                let stored = map([guide], toDisplay: false)
                if model.setUprightGuides(stored, add: true) {
                    guides = Array((guides + stored).suffix(4))
                    display = Array((display + [guide]).suffix(4))
                } else {
                    reload()
                }
            }
    }

    private func delete(_ index: Int) {
        guard display.indices.contains(index) else { return }
        var rest = display
        rest.remove(at: index)
        commit(rest)
    }

    /// VoiceOver: move one endpoint by a fixed step (displayed frame), committed as one `geometry.guides`.
    private func nudge(_ index: Int, end: Int, dx: CGFloat, dy: CGFloat) {
        guard display.indices.contains(index) else { return }
        var updated = display
        func moved(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x + dx, 0), 1), y: min(max(p.y + dy, 0), 1))
        }
        if end == 0 { updated[index].a = moved(updated[index].a) } else { updated[index].b = moved(updated[index].b) }
        guard lengthInPoints(updated[index]) > Self.minLengthPoints else { return }
        commit(updated)
    }
}
