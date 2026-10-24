import SwiftUI
@preconcurrency import LightCraftKit

/// iPad: vertical panel and tool switcher on the trailing edge of the loupe. Degradation order (cookbook §4):
/// full size, then denser, then the buttons that still do not fit move into a "More" menu. It never scrolls
/// (a ScrollView made the later buttons unhittable) and never lets a button silently fall off screen.
struct PanelSwitcher: View {
    let model: LibraryModel

    /// Button edge and gap, densest last. The first density that fits every button wins.
    private static let densities: [(edge: CGFloat, gap: CGFloat)] = [(40, 8), (34, 6), (30, 4)]
    private static let verticalPadding: CGFloat = 8
    private static let dividerHeight: CGFloat = 1

    private enum Entry: Identifiable {
        case panel(Panel)
        case tool(Tool)
        var id: String {
            switch self {
            case .panel(let p): p.uiID
            case .tool(let t): t.uiID
            }
        }
    }

    private var entries: [Entry] { Panel.allCases.map(Entry.panel) + Tool.allCases.map(Entry.tool) }

    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(count: entries.count, height: geo.size.height)
            let shown = Array(entries.prefix(layout.visible))
            let hidden = Array(entries.dropFirst(layout.visible))
            let panels = shown.filter { if case .panel = $0 { true } else { false } }
            let tools = shown.filter { if case .tool = $0 { true } else { false } }
            GlassEffectContainer(spacing: layout.gap) {
                VStack(spacing: layout.gap) {
                    ForEach(panels) { button($0, edge: layout.edge) }
                    if !panels.isEmpty && !tools.isEmpty { Divider().frame(width: 32) }
                    ForEach(tools) { button($0, edge: layout.edge) }
                    if !hidden.isEmpty { moreMenu(hidden, edge: layout.edge) }
                }
                .padding(.vertical, Self.verticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 70)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panelSwitcher")
    }

    /// How many of the `count` entries are shown directly at the densest size that fits; the rest go in More
    /// (which itself takes one slot). The divider counts against the height as one extra gap + hairline.
    private static func layout(count: Int, height: CGFloat) -> (edge: CGFloat, gap: CGFloat, visible: Int) {
        let usable = max(0, height - verticalPadding * 2)
        func needed(_ n: Int, _ d: (edge: CGFloat, gap: CGFloat)) -> CGFloat {
            CGFloat(n) * d.edge + CGFloat(max(n - 1, 0)) * d.gap + d.gap + dividerHeight
        }
        for d in densities where needed(count, d) <= usable { return (d.edge, d.gap, count) }
        let d = densities[densities.count - 1]
        // Room for n buttons plus the More button.
        var n = count - 1
        while n > 0 && needed(n + 1, d) > usable { n -= 1 }
        return (d.edge, d.gap, max(n, 0))
    }

    @ViewBuilder
    private func button(_ entry: Entry, edge: CGFloat) -> some View {
        switch entry {
        case .panel(let panel):
            let selected = model.isPanelShown(panel)
            Button {
                model.togglePanel(panel)
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
        case .tool(let tool):
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

    private func moreMenu(_ hidden: [Entry], edge: CGFloat) -> some View {
        Menu {
            ForEach(hidden) { entry in
                switch entry {
                case .panel(let panel):
                    Button { model.showPanel(panel) } label: { Label(panel.uiTitle, systemImage: panel.uiSymbol) }
                        .accessibilityIdentifier("panelSwitcher.more.\(panel.uiID)")
                case .tool(let tool):
                    Button { model.runUI(tool.uiID) } label: { Label(tool.uiTitle, systemImage: tool.uiSymbol) }
                        .accessibilityIdentifier("panelSwitcher.more.\(tool.uiID)")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(edge < 40 ? .body : .title3)
                .frame(width: edge, height: edge)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("panelSwitcher.more")
    }
}
