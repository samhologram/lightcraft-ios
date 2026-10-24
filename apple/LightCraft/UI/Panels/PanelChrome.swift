import SwiftUI
@preconcurrency import LightCraftKit

/// The iPhone panel sheet's chooser; iPad uses the persistent inspector dock's Add menu.
struct PanelsMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            ForEach(Panel.allCases) { panel in
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
    @State private var addMaskOpen = false
    @State private var findOpen = false
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
                Button {
                    findOpen = true
                } label: {
                    glyph("Find", "sparkles")
                }
                .disabled(model.activePhoto == nil)
                .accessibilityLabel("Find")
                .accessibilityIdentifier("panel.remove.find")
                .popover(isPresented: $findOpen, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            findOpen = false
                            model.run("spot.findDust")
                        } label: {
                            Label("Find Dust Spots", systemImage: "sparkles")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.isEnabled("spot.findDust"))
                        .accessibilityIdentifier("command.spot.findDust")
                        Button {
                            findOpen = false
                            model.run("spot.findBlemishes")
                        } label: {
                            Label("Find Blemishes", systemImage: "face.smiling")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.isEnabled("spot.findBlemishes"))
                        .accessibilityIdentifier("command.spot.findBlemishes")
                        if !model.isEnabled("spot.findBlemishes") {
                            Text(model.handle.disabledReason(id: "spot.findBlemishes") ?? "Face model unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("remove.findBlemishes.reason")
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 240, maxWidth: 300, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            case .masking:
                Button {
                    addMaskOpen = true
                } label: {
                    glyph("Add Mask", "plus")
                }
                .disabled(model.activePhoto == nil)
                .accessibilityLabel("Add Mask")
                .accessibilityIdentifier("panel.masking.add")
                .popover(isPresented: $addMaskOpen, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tools").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        toolItem("tool.brush", "Brush", "paintbrush")
                        toolItem("tool.linear", "Linear Gradient", "rectangle.split.1x2")
                        toolItem("tool.radial", "Radial Gradient", "circle.dashed")
                        Divider()
                        Text("Select").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        kindItem("subject", "Subject", "person.crop.square")
                        kindItem("sky", "Sky", "cloud.sun")
                        kindItem("background", "Background", "rectangle.dashed")
                        Divider()
                        Button { addMaskOpen = false; model.runUI("view.maskOverlay") } label: {
                            Label("Show Overlay", systemImage: "eye")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("view.maskOverlay")
                    }
                    .padding(16)
                    .frame(minWidth: 220, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
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
        Button { addMaskOpen = false; model.runUI(id) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func kindItem(_ kind: String, _ title: String, _ symbol: String) -> some View {
        Button { addMaskOpen = false; model.run("mask.add", ["kind": kind]) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
            .buttonStyle(.plain)
            .accessibilityIdentifier("command.mask.add.\(kind)")
    }
}
