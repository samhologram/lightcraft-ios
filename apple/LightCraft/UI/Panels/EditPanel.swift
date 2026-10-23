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
    // Kept: HSL band swatches show the actual hue being edited, not UI chrome.
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
                        ForEach(order, id: \.self) { sid in
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

    /// The desktop's rules: the B&W mixer replaces the colour mixer for a B&W edit.
    private var order: [String] {
        Self.order.filter { model.isBlackAndWhite ? $0 != "mixer" : $0 != "bwMix" }
    }

    private var header: some View {
        // Labels and icons when they fit, icons only on a narrow inspector (never a wrapped word).
        ViewThatFits(in: .horizontal) {
            headerButtons(titles: true)
            headerButtons(titles: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func headerButtons(titles: Bool) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                headerButton("Auto", "wand.and.stars", id: "develop.auto", titles: titles) { model.run("develop.auto") }
                headerButton("B&W", "circle.lefthalf.filled", id: "develop.treatment", titles: titles,
                             on: model.isBlackAndWhite) { model.run("develop.treatment") }
                headerButton("HDR", "sun.max", id: "develop.hdr", titles: titles, on: model.hdrEnabled) {
                    model.run("develop.hdr", ["enabled": !model.hdrEnabled])
                }
                Spacer(minLength: 0)
                headerButton("Reset", "arrow.counterclockwise", id: "develop.reset", titles: titles, role: .destructive) {
                    model.run("develop.reset")
                }
            }
        }
    }

    private func headerButton(_ title: String, _ symbol: String, id: String, titles: Bool, on: Bool = false,
                              role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Group {
                if titles {
                    Label(title, systemImage: symbol).labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
                } else {
                    Image(systemName: symbol).frame(minWidth: 24)
                }
            }
        }
        .buttonStyle(.glass)
        .tint(on ? .accentColor : nil)
        .disabled(!model.isEnabled(id))
        .accessibilityLabel(title)
        .accessibilityIdentifier("command.\(id)")
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
        switch sid {
        case "mixer": items.filter { $0.id.hasPrefix("mixer.\(band).") }
        // HDR headroom and the SDR rendition only exist while HDR editing is on.
        case "light": model.hdrEnabled ? items : items.filter { !$0.id.hasPrefix("hdr.") }
        default: items
        }
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
