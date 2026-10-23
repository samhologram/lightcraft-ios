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

/// Label left, value right, a tinted track below. Drag moves the value (one begin/end pair per drag),
/// double-tap resets, VoiceOver adjusts in steps. Used by the develop controls and the mask sliders.
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

    @State private var dragValue: Double?

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
                Spacer(minLength: 8)
                Text(verbatim: formatted)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { g in
                            let frac = min(1, max(0, (g.location.x - thumb / 2) / usable))
                            let v = snapped(range.lowerBound + Double(frac) * (range.upperBound - range.lowerBound))
                            if dragValue == nil { onBegin() }
                            if dragValue != v {
                                dragValue = v
                                onChange(v)
                            }
                        }
                        .onEnded { _ in
                            if dragValue != nil { onEnd() }
                            dragValue = nil
                        }
                )
            }
            .frame(height: 30)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onReset() }
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
