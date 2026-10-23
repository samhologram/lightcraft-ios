import SwiftUI
@preconcurrency import LightCraftKit

/// The Edit panel, generated from `developControls()`: collapsible sections of develop sliders.
struct EditPanel: View {
    let model: LibraryModel

    @State private var expanded: Set<String> = ["light"]
    @State private var band = "red"

    private static let controls: [ControlInfo] = developControls()
    private static let groups: [String: [ControlInfo]] = Dictionary(grouping: controls, by: \.sectionId)

    /// Desktop order; sections that belong to other panels (profile, point color, red eye) are left out.
    private static let order = [
        "light", "color", "effects", "detail", "optics", "geometry", "vignette", "grain",
        "mixer", "grading", "calibration", "curve", "bwMix",
    ]
    private static let bands = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    private static let bandTints: [Color] = [
        Color(red: 0.88, green: 0.25, blue: 0.23), Color(red: 0.91, green: 0.54, blue: 0.19),
        Color(red: 0.91, green: 0.82, blue: 0.23), Color(red: 0.25, green: 0.69, blue: 0.31),
        Color(red: 0.19, green: 0.75, blue: 0.75), Color(red: 0.23, green: 0.38, blue: 0.88),
        Color(red: 0.54, green: 0.25, blue: 0.82), Color(red: 0.82, green: 0.25, blue: 0.66),
    ]

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to edit it.")
        } else {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Self.order, id: \.self) { sid in
                            if let items = Self.groups[sid], let title = items.first?.section {
                                section(sid, title, items)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.run("develop.auto") } label: { Label("Auto", systemImage: "wand.and.stars") }
                    .buttonStyle(.glass)
                    .disabled(!model.isEnabled("develop.auto"))
                    .accessibilityIdentifier("command.develop.auto")
                Button { model.run("develop.treatment") } label: { Label("B&W", systemImage: "circle.lefthalf.filled") }
                    .buttonStyle(.glass)
                    .disabled(!model.isEnabled("develop.treatment"))
                    .accessibilityIdentifier("command.develop.treatment")
                Spacer(minLength: 0)
                Button(role: .destructive) { model.run("develop.reset") } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.glass)
                    .disabled(!model.isEnabled("develop.reset"))
                    .accessibilityIdentifier("command.develop.reset")
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func isExpanded(_ sid: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(sid) },
            set: { if $0 { expanded.insert(sid) } else { expanded.remove(sid) } }
        )
    }

    private func section(_ sid: String, _ title: String, _ items: [ControlInfo]) -> some View {
        VStack(spacing: 0) {
        DisclosureGroup(isExpanded: isExpanded(sid)) {
            VStack(spacing: 6) {
                if sid == "mixer" { bandPicker }
                ForEach(visibleItems(sid, items), id: \.id) { control in
                    DevelopSlider(model: model, control: control)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(verbatim: title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("section.\(sid)")
        }
        .padding(.vertical, 8)
        Divider()
        }
    }

    private func visibleItems(_ sid: String, _ items: [ControlInfo]) -> [ControlInfo] {
        sid == "mixer" ? items.filter { $0.id.hasPrefix("mixer.\(band).") } : items
    }

    private var bandPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(Self.bands.enumerated()), id: \.offset) { i, name in
                    Button {
                        band = name
                    } label: {
                        Circle()
                            .fill(Self.bandTints[i])
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary, lineWidth: band == name ? 2.5 : 0).padding(-3))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.capitalized)
                    .accessibilityAddTraits(band == name ? .isSelected : [])
                    .accessibilityIdentifier("mixer.band.\(name)")
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }
}
