import SwiftUI
@preconcurrency import LightCraftKit

/// The "Panels" menu (`control.panels`): iPad shows / hides each panel in the inspector column
/// (`control.panels.<id>`, checkmarked) with layout shortcuts; iPhone opens the chosen panel in the sheet.
struct PanelsMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            ForEach(Panel.allCases) { panel in
                if model.panelsAsSheet {
                    Button {
                        model.showPanel(panel)
                    } label: {
                        if model.isPanelShown(panel) {
                            Label(panel.uiTitle, systemImage: "checkmark")
                        } else {
                            Label(panel.uiTitle, systemImage: panel.uiSymbol)
                        }
                    }
                    .accessibilityIdentifier("control.panels.\(panel.rawValue)")
                } else {
                    Toggle(isOn: Binding(
                        get: { model.isPanelShown(panel) },
                        set: { on in if on { model.showPanel(panel) } else { model.hidePanel(panel) } }
                    )) {
                        Label(panel.uiTitle, systemImage: panel.uiSymbol)
                    }
                    .accessibilityIdentifier("control.panels.\(panel.rawValue)")
                }
            }
            if !model.panelsAsSheet {
                Divider()
                Button { model.expandAllPanels() } label: { Label("Expand All", systemImage: "chevron.down") }
                    .accessibilityIdentifier("control.panels.expandAll")
                Button { model.collapseAllPanels() } label: { Label("Collapse All", systemImage: "chevron.right") }
                    .accessibilityIdentifier("control.panels.collapseAll")
                Button { model.resetPanelLayout() } label: { Label("Reset Panel Layout", systemImage: "arrow.counterclockwise") }
                    .accessibilityIdentifier("control.panels.reset")
            }
        } label: {
            Label("Panels", systemImage: "square.stack.3d.up")
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Panels")
        .accessibilityIdentifier("control.panels")
    }
}

/// The actions a panel owns, shown in its header (as on the desktop), never in the global toolbar.
/// Command identifiers (`command.<id>`) are the ones the actions had inside the panel bodies.
struct PanelHeaderActions: View {
    let model: LibraryModel
    let panel: Panel

    @State private var confirmClear = false
    @AppStorage("redeye.pet") private var redEyePet = false

    var body: some View {
        HStack(spacing: 0) {
            switch panel {
            case .edit:
                icon("Auto", "wand.and.stars", id: "develop.auto") { model.run("develop.auto") }
                icon("Reset", "arrow.counterclockwise", id: "develop.reset", role: .destructive) { model.run("develop.reset") }
            case .crop:
                icon("Reset Crop", "arrow.counterclockwise", id: "crop.reset", role: .destructive) { model.run("crop.reset") }
            case .remove:
                Menu {
                    Button { model.run("spot.findDust") } label: { Label("Find Dust Spots", systemImage: "sparkles") }
                        .disabled(!model.isEnabled("spot.findDust"))
                        .accessibilityIdentifier("command.spot.findDust")
                    Button { model.run("spot.findBlemishes") } label: { Label("Find Blemishes", systemImage: "face.smiling") }
                        .disabled(!model.isEnabled("spot.findBlemishes"))
                        .accessibilityIdentifier("command.spot.findBlemishes")
                    Divider()
                    Button { model.runUI("view.toolOverlay") } label: { Label("Cycle Tool Overlay", systemImage: "eye") }
                        .accessibilityIdentifier("view.toolOverlay")
                } label: {
                    glyph("Find", "sparkles")
                }
                .disabled(model.activePhoto == nil)
                .accessibilityLabel("Find")
                .accessibilityIdentifier("panel.remove.find")
            case .masking:
                Menu {
                    Section("Tools") {
                        toolItem("tool.brush", "Brush", "paintbrush")
                        toolItem("tool.linear", "Linear Gradient", "rectangle.split.1x2")
                        toolItem("tool.radial", "Radial Gradient", "circle.dashed")
                    }
                    Section("Select") {
                        kindItem("subject", "Subject", "person.crop.square")
                        kindItem("sky", "Sky", "cloud.sun")
                        kindItem("background", "Background", "rectangle.dashed")
                    }
                    Divider()
                    Button { model.runUI("view.maskOverlay") } label: { Label("Show Overlay", systemImage: "eye") }
                        .accessibilityIdentifier("view.maskOverlay")
                } label: {
                    glyph("Add Mask", "plus")
                }
                .disabled(model.activePhoto == nil)
                .accessibilityLabel("Add Mask")
                .accessibilityIdentifier("panel.masking.add")
            case .redeye:
                icon("Add Correction", "plus", id: "redeye.add") {
                    model.run("redeye.add", ["center": [0.5, 0.5], "rx": 0.03, "ry": 0.03, "pet": redEyePet])
                }
            case .presets:
                icon("New Preset", "plus", id: "preset.create", enabled: model.activePhoto != nil) { model.present("preset.create") }
                icon("Import Presets", "square.and.arrow.down", id: "file.importPresets", enabled: true) { model.runUI("file.importPresets") }
            case .versions:
                icon("New Version", "plus", id: "version.create", enabled: model.activePhoto != nil) { model.run("version.create") }
            case .activity:
                Button {
                    model.run("version.create")
                } label: {
                    glyph("Snapshot", "camera")
                }
                .disabled(model.activePhoto == nil)
                .accessibilityLabel("Snapshot")
                .accessibilityIdentifier("panel.activity.snapshot")
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    glyph("Clear History", "trash")
                }
                .disabled(!model.isEnabled("history.clear"))
                .accessibilityLabel("Clear History")
                .accessibilityIdentifier("command.history.clear")
            case .profiles, .info, .keywords:
                EmptyView()
            }
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Clear the history of this photo?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { model.run("history.clear") }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func glyph(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
    }

    private func icon(_ title: String, _ symbol: String, id: String, role: ButtonRole? = nil, enabled: Bool? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { glyph(title, symbol) }
            .disabled(!(enabled ?? model.isEnabled(id)))
            .accessibilityLabel(title)
            .accessibilityIdentifier("command.\(id)")
    }

    private func toolItem(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { model.runUI(id) } label: { Label(title, systemImage: symbol) }
            .accessibilityIdentifier(id)
    }

    private func kindItem(_ kind: String, _ title: String, _ symbol: String) -> some View {
        Button { model.run("mask.add", ["kind": kind]) } label: { Label(title, systemImage: symbol) }
            .accessibilityIdentifier("command.mask.add.\(kind)")
    }
}
