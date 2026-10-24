import SwiftUI
@preconcurrency import LightCraftKit

/// iPad inspector dock: PhotoCraft-style stacked groups of persistent panel tabs.
struct InspectorColumn: View {
    let model: LibraryModel

    private static let stripHeight: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            dockHeader
                .background(.bar)
                .zIndex(1)
            if model.panelLayout.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Panels", systemImage: "rectangle.stack")
                } description: {
                    Text("Add a panel with the plus button.")
                } actions: {
                    Button("Show Edit") { model.showPanel(.edit) }
                        .accessibilityIdentifier("control.panelMenu.showEdit")
                }
            } else {
                GeometryReader { geometry in
                    ScrollViewReader { reader in
                        ScrollView(.vertical) {
                            VStack(spacing: 8) {
                                ForEach(Array(model.panelLayout.groups.enumerated()), id: \.element.id) { index, group in
                                    DockGroupView(model: model, group: group, index: index,
                                                  revealTick: model.panelRevealTick,
                                                  contentHeight: max(260, geometry.size.height - CGFloat(model.panelLayout.groups.count) * Self.stripHeight - 70))
                                        .id(group.id)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .onChange(of: model.panelRevealTick, initial: true) { _, _ in
                            guard let target = model.panelRevealTarget,
                                  let group = model.panelLayout.groups.first(where: { $0.tabs.contains(target) }) else { return }
                            withAnimation(.smooth) { reader.scrollTo(group.id, anchor: .top) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }

    private var dockHeader: some View {
        HStack(spacing: 8) {
            Text("Panels")
                .font(.headline)
                .accessibilityIdentifier("panelTitle")
            Spacer()
            Menu {
                ForEach(Panel.allCases) { panel in
                    Button {
                        model.showPanel(panel)
                    } label: {
                        Label(panel.title, systemImage: model.panelLayout.isVisible(panel) ? "checkmark" : panel.symbol)
                    }
                    .accessibilityIdentifier("control.panelMenu.\(panel.rawValue)")
                }
                Divider()
                Button("Reset Panels") { model.resetPanelLayout() }
                    .accessibilityIdentifier("control.panelMenu.reset")
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Add Panel")
            .accessibilityIdentifier("control.panelMenu")

            Button {
                model.inspectorVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close panel dock")
            .accessibilityIdentifier("panel.close")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct DockGroupView: View {
    let model: LibraryModel
    let group: PanelDockGroup
    let index: Int
    let revealTick: Int
    let contentHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            strip
            if !group.collapsed {
                Divider()
                HStack {
                    Text(group.selected.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("panel.\(group.selected.rawValue).header")
                    Spacer(minLength: 4)
                    PanelHeaderActions(model: model, panel: group.selected)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(.bar)
                .accessibilityElement(children: .contain)
                PanelBody(panel: group.selected, model: model)
                    .id(group.selected)
                    .frame(height: contentHeight)
                    .clipped()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("panel.\(group.selected.rawValue)")
            }
        }
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panelGroup.\(index)")
    }

    private var strip: some View {
        HStack(spacing: 4) {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(group.tabs) { panel in
                            tab(panel)
                                .id(panel)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: group.selected, initial: true) { _, selected in
                    withAnimation(.smooth) { reader.scrollTo(selected, anchor: .center) }
                }
                .onChange(of: revealTick) { _, _ in
                    guard model.panelRevealTarget == group.selected else { return }
                    withAnimation(.smooth) { reader.scrollTo(group.selected, anchor: .center) }
                }
            }
            Button {
                withAnimation(.smooth) { model.togglePanelCollapsed(group.selected) }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(group.collapsed ? -90 : 0))
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(group.collapsed ? "Expand" : "Collapse")
            .accessibilityIdentifier("panelCollapse.\(index)")
            Menu {
                Button(group.collapsed ? "Expand" : "Collapse") {
                    model.togglePanelCollapsed(group.selected)
                }
                Button("Move Up") { model.movePanel(group.selected, by: -1) }
                    .disabled(index == 0)
                Button("Move Down") { model.movePanel(group.selected, by: 1) }
                    .disabled(index == model.panelLayout.groups.count - 1)
                Divider()
                Button(role: .destructive) {
                    for panel in group.tabs { model.hidePanel(panel) }
                } label: { Label("Close Group", systemImage: "xmark") }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Group Options")
            .accessibilityIdentifier("panelGroup.\(index).menu")
        }
        .padding(.trailing, 4)
        .frame(height: 46)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let panel = Panel(rawValue: raw) else { return false }
            model.movePanel(panel, before: group.selected)
            return true
        }
    }

    private func tab(_ panel: Panel) -> some View {
        let selected = panel == group.selected
        return Button {
            model.selectPanelTab(panel)
        } label: {
            Group {
                if selected { Label(panel.title, systemImage: panel.symbol) }
                else { Text(panel.title) }
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .glassEffect(selected ? .regular.interactive() : .identity, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityIdentifier("panelTab.\(panel.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .draggable(panel.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dropped = Panel(rawValue: raw) else { return false }
            model.movePanel(dropped, before: panel)
            return true
        }
        .contextMenu {
            if group.tabs.count > 1 {
                Button("Move to New Group") { model.movePanelToNewGroup(panel) }
            }
            Button(role: .destructive) {
                model.hidePanel(panel)
            } label: { Label("Close", systemImage: "xmark") }
        }
    }
}
