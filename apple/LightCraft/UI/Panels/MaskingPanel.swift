import SwiftUI
@preconcurrency import LightCraftKit

/// Masking: create a mask (tools or AI kinds), the mask list, and the selected mask's effect sliders.
struct MaskingPanel: View {
    let model: LibraryModel

    private struct MaskRow: Identifiable {
        let id: UInt32
        let name: String
        let visible: Bool
        let invert: Bool
        let kinds: String
        let adjust: [String: Double]
    }

    private struct Effect {
        let key: String
        let label: String
        let lo: Double
        let hi: Double
        let step: Double
        let decimals: Int
        let track: SliderTrack
    }

    // Kept: white-balance preview gradients, content colour.
    private static let tempTrack = SliderTrack.gradient([Color(red: 0.23, green: 0.48, blue: 0.84), Color(red: 0.94, green: 0.82, blue: 0.23)])
    private static let tintTrack = SliderTrack.gradient([Color(red: 0.25, green: 0.73, blue: 0.31), Color(red: 0.84, green: 0.25, blue: 0.66)])

    private static let effectGroups: [(title: String, effects: [Effect])] = [
        ("Light", [
            Effect(key: "exposure", label: "Exposure", lo: -4, hi: 4, step: 0.01, decimals: 2, track: .centered),
            Effect(key: "contrast", label: "Contrast", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "highlights", label: "Highlights", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "shadows", label: "Shadows", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "whites", label: "Whites", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "blacks", label: "Blacks", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
        ]),
        ("Color", [
            Effect(key: "temp", label: "Temp", lo: -100, hi: 100, step: 1, decimals: 0, track: MaskingPanel.tempTrack),
            Effect(key: "tint", label: "Tint", lo: -100, hi: 100, step: 1, decimals: 0, track: MaskingPanel.tintTrack),
            Effect(key: "saturation", label: "Saturation", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "hue", label: "Hue", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
        ]),
        ("Effects", [
            Effect(key: "texture", label: "Texture", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "clarity", label: "Clarity", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "dehaze", label: "Dehaze", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
        ]),
        ("Detail", [
            Effect(key: "sharpness", label: "Sharpness", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "noise", label: "Noise", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "moire", label: "Moiré", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
            Effect(key: "defringe", label: "Defringe", lo: -100, hi: 100, step: 1, decimals: 0, track: .centered),
        ]),
    ]

    @State private var masks: [MaskRow] = []
    @State private var expanded: Set<String> = ["Light"]

    private var activeMask: MaskRow? {
        guard let id = model.state.activeMask else { return nil }
        return masks.first { $0.id == id }
    }

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to add masks.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    creation
                    if !masks.isEmpty { list }
                    if let mask = activeMask { effects(mask) }
                }
                .padding(16)
            }
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: model.state.active) { _, _ in reload() }
        }
    }

    // MARK: Create

    private var creation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Mask").font(.headline)
            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    toolButton("tool.brush", "Brush", "paintbrush", model.activeTool?.rawValue == "brush")
                    toolButton("tool.linear", "Linear", "rectangle.split.1x2", model.activeTool?.rawValue == "linear")
                    toolButton("tool.radial", "Radial", "circle.dashed", model.activeTool?.rawValue == "radial")
                    kindButton("subject", "Subject", "person.crop.square")
                    kindButton("sky", "Sky", "cloud.sun")
                    kindButton("background", "Background", "rectangle.dashed")
                }
            }
            Button {
                model.runUI("view.maskOverlay")
            } label: {
                Label("Show Overlay", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("view.maskOverlay")
        }
    }

    private func toolButton(_ id: String, _ title: String, _ symbol: String, _ active: Bool) -> some View {
        Button {
            model.runUI(id)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity).lineLimit(1)
        }
        .glassToggle(active)
        .accessibilityIdentifier(id)
    }

    private func kindButton(_ kind: String, _ title: String, _ symbol: String) -> some View {
        Button {
            model.run("mask.add", ["kind": kind])
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity).lineLimit(1)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("command.mask.add.\(kind)")
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Masks").font(.headline)
            ForEach(masks) { mask in
                let selected = model.state.activeMask == mask.id
                HStack(spacing: 4) {
                    Button {
                        model.run("mask.select", ["id": mask.id])
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: mask.name).font(.subheadline.weight(.medium))
                            Text(verbatim: mask.kinds).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("mask.\(mask.id)")
                    iconButton(mask.visible ? "eye" : "eye.slash", "Show or hide", "command.mask.visible") {
                        model.run("mask.visible", ["id": mask.id, "visible": !mask.visible])
                    }
                    iconButton("circle.lefthalf.filled", "Invert", "command.mask.invert", active: mask.invert) {
                        model.run("mask.invert", ["id": mask.id])
                    }
                    iconButton("trash", "Delete", "command.mask.delete") {
                        model.run("mask.delete", ["id": mask.id])
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, _ id: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: Effects

    @ViewBuilder
    private func effects(_ mask: MaskRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Effect · \(mask.name)").font(.headline)
            ForEach(Self.effectGroups, id: \.title) { group in
                DisclosureGroup(isExpanded: Binding(
                    get: { expanded.contains(group.title) },
                    set: { if $0 { expanded.insert(group.title) } else { expanded.remove(group.title) } }
                )) {
                    VStack(spacing: 6) {
                        ForEach(group.effects, id: \.key) { e in slider(mask, e) }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(verbatim: group.title).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("section.mask.\(group.title.lowercased())")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func slider(_ mask: MaskRow, _ e: Effect) -> some View {
        ValueSlider(
            identifier: "control.mask.\(e.key)",
            label: e.label,
            range: e.lo...e.hi,
            defaultValue: 0,
            step: e.step,
            decimals: e.decimals,
            track: e.track,
            value: mask.adjust[e.key] ?? 0,
            onBegin: { model.beginDrag("Mask \(e.label)") },
            onChange: { model.run("mask.adjust", ["id": mask.id, "values": [e.key: $0]]) },
            onEnd: { model.endDrag() },
            onReset: { model.run("mask.adjust", ["id": mask.id, "values": [e.key: 0]]) }
        )
    }

    // MARK: Data

    private func reload() {
        guard let id = model.state.active,
              let dev = EngineQuery.develop(model, id),
              let list = dev["masks"] as? [[String: Any]] else {
            masks = []
            return
        }
        masks = list.compactMap { m in
            guard let mid = (m["id"] as? NSNumber)?.uint32Value else { return nil }
            let comps = (m["components"] as? [[String: Any]]) ?? []
            let kinds = comps.compactMap { ($0["shape"] as? [String: Any])?["kind"] as? String }
            var adjust: [String: Double] = [:]
            for (k, v) in (m["adjust"] as? [String: Any]) ?? [:] {
                if let d = jsonNumber(v) { adjust[k] = d }
            }
            return MaskRow(
                id: mid,
                name: (m["name"] as? String) ?? "Mask \(mid)",
                visible: (m["visible"] as? Bool) ?? true,
                invert: (m["invert"] as? Bool) ?? false,
                kinds: kinds.isEmpty ? "Empty" : kinds.map { $0.capitalized }.joined(separator: " + "),
                adjust: adjust
            )
        }
    }
}
