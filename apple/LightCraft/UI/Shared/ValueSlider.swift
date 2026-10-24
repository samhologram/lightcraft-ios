import SwiftUI
@preconcurrency import LightCraftKit

// Kept: slider tracks preview the colour effect (white balance, hue bands, grading wheels).
private extension Color {
    /// "#rrggbb" (or "rrggbb") to a colour; mid grey when unparsable.
    init(lcHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = Color(white: 0.5)
            return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// How a slider track is painted.
enum SliderTrack: Equatable {
    /// Grey track filled from the minimum.
    case plain
    /// Grey track filled from the middle (zero in the centre).
    case centered
    /// The whole track is a colour gradient (white balance, hue bands, grading…).
    case gradient([Color])

    private static let bandNames = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    private static let bandColors: [Color] = [
        Color(lcHex: "#e0403a"), Color(lcHex: "#e88a30"), Color(lcHex: "#e8d03a"), Color(lcHex: "#40b050"),
        Color(lcHex: "#30c0c0"), Color(lcHex: "#3a60e0"), Color(lcHex: "#8a40d0"), Color(lcHex: "#d040a8"),
    ]

    private static func band(of id: String) -> Int {
        for part in id.split(separator: ".") {
            if let i = bandNames.firstIndex(of: String(part)) { return i }
        }
        return 0
    }

    init(control c: ControlInfo) {
        switch c.track {
        case "centered": self = .centered
        case "temp": self = .gradient([Color(lcHex: "#3a7bd5"), Color(lcHex: "#f0d03a")])
        case "tint": self = .gradient([Color(lcHex: "#3fb950"), Color(lcHex: "#d63fa8")])
        case "gradient":
            let colors = c.gradient.map { Color(lcHex: $0) }
            self = colors.count >= 2 ? .gradient(colors) : .plain
        case "hue":
            let i = Self.band(of: c.id), n = Self.bandColors.count
            self = .gradient([Self.bandColors[(i + n - 1) % n], Self.bandColors[i], Self.bandColors[(i + 1) % n]])
        case "sat":
            self = .gradient([Color(white: 0.5), Self.bandColors[Self.band(of: c.id)]])
        case "lum":
            let b = Self.bandColors[Self.band(of: c.id)]
            self = .gradient([b.mix(with: .black, by: 0.7), b, b.mix(with: .white, by: 0.8)])
        case "rainbow":
            self = .gradient(stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 0.85, brightness: 0.95) })
        default: self = .plain
        }
    }
}

/// Label left, value right, a tinted track below. Drag anywhere on the row to scrub (relative, and the slower
/// the finger moves the finer the steps; one begin/end pair per drag), double-tap resets, tap the value to type
/// an exact one (Return or Done commits, clamped to the range), VoiceOver adjusts in steps.
/// Ids: `control.<id>` (the slider), `control.<id>.value` (the value button / the editable field).
struct ValueSlider: View {
    let identifier: String
    let label: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double
    let decimals: Int
    let track: SliderTrack
    let value: Double
    var onBegin: () -> Void = {}
    var onChange: (Double) -> Void
    var onEnd: () -> Void = {}
    var onReset: () -> Void

    private struct Scrub {
        var raw: Double
        var lastX: CGFloat
        var lastTime: Date
        var speed: Double = 0
        /// nil until the drag has moved far enough to tell its axis; a vertical drag is left to the scroll view.
        var horizontal: Bool?
    }

    @State private var dragValue: Double?
    @State private var scrub: Scrub?
    @State private var rowWidth: CGFloat = 1
    @State private var editing = false
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private let thumb: CGFloat = 24

    private var shown: Double { dragValue ?? value }

    private func fraction(_ v: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (v - range.lowerBound) / span)))
    }

    private func snapped(_ v: Double) -> Double {
        var out = v
        if step > 0 { out = (out / step).rounded() * step }
        out = min(range.upperBound, max(range.lowerBound, out))
        return (out * 1_000_000).rounded() / 1_000_000
    }

    private var formatted: String { String(format: "%.\(decimals)f", shown) }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(verbatim: label)
                    .font(.subheadline)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                valueView
            }
            GeometryReader { geo in
                let width = geo.size.width
                let usable = max(1, width - thumb)
                let f = fraction(shown)
                ZStack(alignment: .leading) {
                    trackView(width: width, fraction: f)
                        .frame(height: 5)
                        .padding(.horizontal, thumb / 2)
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
                        .shadow(color: Color.primary.opacity(0.2), radius: 2, y: 1)
                        .frame(width: thumb, height: thumb)
                        .offset(x: f * usable)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(formatted)
                .accessibilityIdentifier(identifier)
                .accessibilityAdjustableAction { direction in
                    let delta = max(step, (range.upperBound - range.lowerBound) / 50)
                    let v = snapped(shown + (direction == .increment ? delta : -delta))
                    onBegin()
                    onChange(v)
                    onEnd()
                }
                .accessibilityAction(named: Text("Reset")) { onReset() }
                .accessibilityAction(named: Text("Enter Value")) { beginEditing() }
            }
            .frame(height: 30)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .onTapGesture(count: 2) { onReset() }
        .simultaneousGesture(scrubGesture)
    }

    // MARK: Scrubbing

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                var s = scrub ?? Scrub(raw: shown, lastX: g.startLocation.x, lastTime: g.time)
                if s.horizontal == nil {
                    s.horizontal = abs(g.translation.width) >= abs(g.translation.height)
                    if s.horizontal == true {
                        if editing { commitEditing() }
                        if dragValue == nil { onBegin() }
                    }
                }
                guard s.horizontal == true else { scrub = s; return }
                let dx = g.location.x - s.lastX
                let dt = max(0.001, g.time.timeIntervalSince(s.lastTime))
                s.speed = 0.6 * s.speed + 0.4 * Double(abs(dx)) / dt
                // Slow drags are fine adjustments (15 %), fast ones cover the full range across the row.
                let gain = min(1, max(0.15, s.speed / 500))
                let span = range.upperBound - range.lowerBound
                s.raw = min(range.upperBound, max(range.lowerBound, s.raw + Double(dx / max(1, rowWidth - thumb)) * span * gain))
                s.lastX = g.location.x
                s.lastTime = g.time
                scrub = s
                let v = snapped(s.raw)
                if dragValue != v {
                    dragValue = v
                    onChange(v)
                }
            }
            .onEnded { _ in
                if scrub?.horizontal == true, dragValue != nil { onEnd() }
                dragValue = nil
                scrub = nil
            }
    }

    // MARK: Exact entry

    @ViewBuilder
    private var valueView: some View {
        if editing {
            TextField("", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { commitEditing() }
                .onKeyPress(.escape) { cancelEditing(); return .handled }
                .onChange(of: fieldFocused) { _, focused in if !focused { commitEditing() } }
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                    (note.object as? UITextField)?.selectAll(nil)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { commitEditing() }
                            .accessibilityIdentifier("\(identifier).value.done")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(minWidth: 64, maxWidth: 96)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(Text("\(label) value"))
                .accessibilityIdentifier("\(identifier).value")
        } else {
            Button { beginEditing() } label: {
                Text(verbatim: formatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(label) value"))
            .accessibilityValue(formatted)
            .accessibilityHint(Text("Double tap to type a value"))
            .accessibilityIdentifier("\(identifier).value")
        }
    }

    private func beginEditing() {
        text = formatted
        editing = true
        Task { @MainActor in fieldFocused = true }
    }

    private func cancelEditing() {
        editing = false
        fieldFocused = false
    }

    private func commitEditing() {
        guard editing else { return }
        editing = false
        fieldFocused = false
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let typed = Double(cleaned), typed.isFinite else { return }
        let v = (min(range.upperBound, max(range.lowerBound, typed)) * 1_000_000).rounded() / 1_000_000
        guard v != value else { return }
        onBegin()
        onChange(v)
        onEnd()
    }

    @ViewBuilder
    private func trackView(width: CGFloat, fraction f: CGFloat) -> some View {
        let usable = max(1, width - thumb)
        switch track {
        case .gradient(let colors):
            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        case .plain:
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.3))
                Capsule().fill(Color.accentColor).frame(width: usable * f)
            }
        case .centered:
            let mid = usable * fraction(0 < range.lowerBound || 0 > range.upperBound ? (range.lowerBound + range.upperBound) / 2 : 0)
            let x = usable * f
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.3))
                Capsule().fill(Color.accentColor)
                    .frame(width: abs(x - mid))
                    .offset(x: min(x, mid))
            }
        }
    }
}

/// A develop slider generated from a `ControlInfo` (`control.<id>`).
struct DevelopSlider: View {
    let model: LibraryModel
    let control: ControlInfo

    var body: some View {
        ValueSlider(
            identifier: "control.\(control.id)",
            label: control.label,
            range: control.min...max(control.min, control.max),
            defaultValue: control.defaultValue,
            step: control.step,
            decimals: Int(control.decimals),
            track: SliderTrack(control: control),
            value: model.developValues[control.id] ?? control.defaultValue,
            onBegin: { model.beginDrag(control.label) },
            onChange: { model.setDevelop(control.id, $0) },
            onEnd: { model.endDrag() },
            onReset: { model.run("develop.resetControl", ["control": control.id]) }
        )
    }
}
