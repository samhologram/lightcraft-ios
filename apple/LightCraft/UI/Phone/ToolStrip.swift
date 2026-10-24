import SwiftUI
@preconcurrency import LightCraftKit

/// Horizontally scrolling strip of panel (`panel.<id>`) and tool (`tool.<id>`) buttons. Scrolling is the
/// last resort of the degradation order, so nothing can fall off a narrow screen.
struct ToolStrip: View {
    let model: LibraryModel
    var includesTools = true

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    if includesTools {
                        PanelsMenu(model: model)
                        Divider().frame(height: 36)
                    }
                    ForEach(Panel.allCases, id: \.self) { panel in
                        let selected = model.isPanelShown(panel)
                        Button {
                            model.togglePanel(panel)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: panel.uiSymbol).font(.title3)
                                Text(verbatim: panel.uiTitle).font(.caption2).lineLimit(1)
                            }
                            .frame(minWidth: 58)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(panel.uiTitle)
                        }
                        .glassToggle(selected)
                        .accessibilityLabel(panel.uiTitle)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier(panel.uiID)
                    }
                    if includesTools {
                        Divider().frame(height: 36)
                        ForEach(Tool.allCases, id: \.self) { tool in
                            let selected = model.activeTool == tool
                            Button {
                                model.runUI(tool.uiID)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: tool.uiSymbol).font(.title3)
                                    Text(verbatim: tool.uiTitle).font(.caption2).lineLimit(1)
                                }
                                .frame(minWidth: 58)
                            }
                            .glassToggle(selected)
                            .accessibilityLabel(tool.uiTitle)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier(tool.uiID)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
    }
}
