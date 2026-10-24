import SwiftUI
@preconcurrency import LightCraftKit

/// iPad inspector column: the shown panels stacked as sections (Photoshop / Lightroom style). Each section has
/// a header with a disclosure toggle, the panel's own actions and a menu (Move Up / Down, Hide); headers can
/// also be dragged to reorder. The "Panels" menu in the column header shows and hides each panel. The
/// arrangement lives in `LibraryModel.panelLayout` and persists in `AppSettings`.
struct InspectorColumn: View {
    let model: LibraryModel

    private static let headerHeight: CGFloat = 46
    private static let minBodyHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider()
            if model.panelLayout.visiblePanels.isEmpty {
                ContentUnavailableView {
                    Label("No Panels", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("Choose panels to show with the Panels menu.")
                } actions: {
                    Button("Show Edit") { model.showPanel(.edit) }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("control.panels.showEdit")
                }
            } else {
                sections
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Panels")
                .font(.headline)
                .accessibilityIdentifier("panelTitle")
            Spacer()
            PanelsMenu(model: model)
            Button {
                model.inspectorVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .zIndex(1)
            .accessibilityLabel("Close panel")
            .accessibilityIdentifier("panel.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(minHeight: 48)
    }

    private var sections: some View {
        GeometryReader { geo in
            let shown = model.panelLayout.visiblePanels
            let open = shown.filter { !model.panelLayout.isCollapsed($0) }.count
            // Open panels share the column; with many open, each keeps a usable height and the column scrolls.
            let bodyHeight = max(Self.minBodyHeight, (geo.size.height - Self.headerHeight * CGFloat(shown.count)) / CGFloat(max(open, 1)))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(shown) { panel in
                            PanelSection(model: model, panel: panel, bodyHeight: bodyHeight, headerHeight: Self.headerHeight)
                                .id(panel)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.panelRevealTick) { _, _ in scrollToReveal(proxy) }
                // The column may be created by the very tap that opens a panel: its tick change then happened before it existed.
                .onAppear { scrollToReveal(proxy) }
            }
        }
    }
}

extension InspectorColumn {
    /// Scrolls the revealed panel's section to the top. Waits a beat so the expansion (new body heights) has been laid out.
    @MainActor fileprivate func scrollToReveal(_ proxy: ScrollViewProxy) {
        guard let target = model.panelRevealTarget else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard model.panelLayout.visiblePanels.contains(target) else { return }
            withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
        }
    }
}

/// One stacked panel: header (disclosure, title, actions, menu) and, when open, the panel body.
private struct PanelSection: View {
    let model: LibraryModel
    let panel: Panel
    let bodyHeight: CGFloat
    let headerHeight: CGFloat

    var body: some View {
        let collapsed = model.panelLayout.isCollapsed(panel)
        VStack(spacing: 0) {
            header(collapsed: collapsed)
            if !collapsed {
                PanelBody(panel: panel, model: model)
                    .frame(height: bodyHeight)
                    .clipped()
            }
            Divider()
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = Panel(rawValue: raw) else { return false }
            model.movePanel(dragged, before: panel)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel.\(panel.rawValue).section")
    }

    private func header(collapsed: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { model.togglePanelCollapsed(panel) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 14)
                    Label(panel.uiTitle, systemImage: panel.uiSymbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(panel.uiTitle)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("panel.\(panel.rawValue).collapse")
            if !collapsed {
                PanelHeaderActions(model: model, panel: panel)
            }
            Menu {
                Button { model.movePanel(panel, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                    .disabled(!model.canMovePanel(panel, by: -1))
                    .accessibilityIdentifier("panel.\(panel.rawValue).moveUp")
                Button { model.movePanel(panel, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                    .disabled(!model.canMovePanel(panel, by: 1))
                    .accessibilityIdentifier("panel.\(panel.rawValue).moveDown")
                Divider()
                Button(role: .destructive) { model.hidePanel(panel) } label: { Label("Hide Panel", systemImage: "eye.slash") }
                    .accessibilityIdentifier("panel.\(panel.rawValue).hide")
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Panel Options")
            .accessibilityIdentifier("panel.\(panel.rawValue).menu")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: headerHeight)
        .background(Color(uiColor: .secondarySystemBackground))
        .draggable(panel.rawValue)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel.\(panel.rawValue).header")
    }
}
