import SwiftUI
@preconcurrency import LightCraftKit

/// iPad: vertical panel and tool switcher on the trailing edge of the loupe. It scrolls when the
/// window is short, so no button is ever out of reach.
struct PanelSwitcher: View {
    let model: LibraryModel

    var body: some View {
        ScrollView(.vertical) {
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(Panel.allCases, id: \.self) { panel in
                        let selected = model.inspectorVisible && model.activePanel == panel
                        Button {
                            uiOpenPanel(panel, model: model, toggle: true)
                        } label: {
                            Image(systemName: panel.uiSymbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                        }
                        .glassToggle(selected)
                        .help(panel.uiTitle)
                        .accessibilityLabel(panel.uiTitle)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier(panel.uiID)
                    }
                    Divider().frame(width: 32)
                    ForEach(Tool.allCases, id: \.self) { tool in
                        let selected = model.activeTool == tool
                        Button {
                            model.runUI(tool.uiID)
                        } label: {
                            Image(systemName: tool.uiSymbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                        }
                        .glassToggle(selected)
                        .help(tool.uiTitle)
                        .accessibilityLabel(tool.uiTitle)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier(tool.uiID)
                    }
                }
                .padding(8)
            }
        }
        .scrollIndicators(.hidden)
        .frame(width: 70)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panelSwitcher")
    }
}
