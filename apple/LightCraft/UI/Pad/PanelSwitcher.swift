import SwiftUI
@preconcurrency import LightCraftKit

/// iPad: vertical panel and tool switcher on the trailing edge of the loupe. It gets denser when
/// the window is short and scrolls only as a last resort, so no button is ever out of reach.
struct PanelSwitcher: View {
    let model: LibraryModel

    /// Button edge and gap, densest last. The first that fits the window height wins; only when even the
    /// densest does not fit does the column scroll (degradation order: denser, then scroll).
    private static let densities: [(edge: CGFloat, gap: CGFloat)] = [(40, 8), (34, 6), (30, 4)]

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(Self.densities.enumerated()), id: \.offset) { _, d in
                column(edge: d.edge, gap: d.gap)
            }
            ScrollView(.vertical) {
                column(edge: Self.densities[Self.densities.count - 1].edge, gap: Self.densities[Self.densities.count - 1].gap)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 70)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panelSwitcher")
    }

    private func column(edge: CGFloat, gap: CGFloat) -> some View {
        GlassEffectContainer(spacing: gap) {
            VStack(spacing: gap) {
                ForEach(Panel.allCases, id: \.self) { panel in
                    let selected = model.inspectorVisible && model.activePanel == panel
                    Button {
                        uiOpenPanel(panel, model: model, toggle: true)
                    } label: {
                        Image(systemName: panel.uiSymbol)
                            .font(edge < 40 ? .body : .title3)
                            .frame(width: edge, height: edge)
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
                            .font(edge < 40 ? .body : .title3)
                            .frame(width: edge, height: edge)
                    }
                    .glassToggle(selected)
                    .help(tool.uiTitle)
                    .accessibilityLabel(tool.uiTitle)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(tool.uiID)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}
