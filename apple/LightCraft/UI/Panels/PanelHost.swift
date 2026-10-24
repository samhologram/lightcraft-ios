import SwiftUI
@preconcurrency import LightCraftKit

/// The body of one panel (no chrome).
struct PanelBody: View {
    let panel: Panel
    let model: LibraryModel

    var body: some View {
        switch panel {
        case .edit: EditPanel(model: model)
        case .profiles: ProfilesPanel(model: model)
        case .crop: CropPanel(model: model)
        case .remove: RemovePanel(model: model)
        case .masking: MaskingPanel(model: model)
        case .redeye: RedEyePanel(model: model)
        case .presets: PresetsPanel(model: model)
        case .info: InfoPanel(model: model)
        case .keywords: KeywordsPanel(model: model)
        case .versions: VersionsPanel(model: model)
        case .activity: ActivityPanel(model: model)
        }
    }
}

/// iPhone panel sheet: the active panel under a header with its actions, the Panels menu and a close button,
/// plus the panel strip. (The iPad shows `InspectorColumn` instead.)
struct PanelHost: View {
    let model: LibraryModel

    var body: some View {
        let panel = model.activePanel
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(panel.uiTitle, systemImage: panel.uiSymbol)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("panelTitle")
                Spacer(minLength: 4)
                PanelHeaderActions(model: model, panel: panel)
                PanelsMenu(model: model)
                Button {
                    model.inspectorVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close panel")
                .accessibilityIdentifier("panel.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("panel.\(panel.rawValue).header")
            ToolStrip(model: model, includesTools: false)
            PanelBody(panel: panel, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
