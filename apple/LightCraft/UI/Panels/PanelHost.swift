import SwiftUI
@preconcurrency import LightCraftKit

/// The body of the active panel (no chrome).
struct ActivePanelView: View {
    let model: LibraryModel

    var body: some View {
        switch model.activePanel {
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

/// The active panel with a title bar and a close button: the iPad inspector column and the iPhone sheet.
struct PanelHost: View {
    let model: LibraryModel
    /// Extra content shown under the title (the iPhone's panel strip).
    var showsSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.activePanel.uiTitle, systemImage: model.activePanel.uiSymbol)
                    .font(.headline)
                    .accessibilityIdentifier("panelTitle")
                Spacer()
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
            if showsSwitcher {
                ToolStrip(model: model, includesTools: false)
            }
            ActivePanelView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
