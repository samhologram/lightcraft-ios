import Foundation

/// Panel state shared by the dock, Window menu and command palette.
extension LibraryModel {
    /// Toolbar and View menu visibility action. Keep the layout intact, including collapsed groups.
    /// A newly mounted dock uses the reveal tick to bring the selected group back into view.
    func toggleInspectorDock() {
        if inspectorVisible {
            inspectorVisible = false
            return
        }
        panelRevealTarget = panelLayout.groupIndex(containing: activePanel) != nil
            ? activePanel : panelLayout.groups.first?.selected
        panelRevealTick += 1
        inspectorVisible = true
    }

    func isPanelShown(_ panel: Panel) -> Bool {
        inspectorVisible && activePanel == panel
    }

    /// Opening a panel selects it in its persistent tab group, or adds a new tab.
    func showPanel(_ panel: Panel) {
        openPanel(panel)
    }

    func togglePanel(_ panel: Panel) {
        if isPanelShown(panel) { inspectorVisible = false }
        else { showPanel(panel) }
    }

    func hidePanel(_ panel: Panel) {
        guard let index = panelLayout.groupIndex(containing: panel) else { return }
        panelLayout.groups[index].tabs.removeAll { $0 == panel }
        if panelLayout.groups[index].tabs.isEmpty {
            panelLayout.groups.remove(at: index)
        } else if panelLayout.groups[index].selected == panel {
            panelLayout.groups[index].selected = panelLayout.groups[index].tabs[0]
        }
        if activePanel == panel, let next = panelLayout.groups.first(where: { !$0.collapsed })?.selected
            ?? panelLayout.groups.first?.selected {
            panelRevealSuppressed = true
            activePanel = next
            panelRevealSuppressed = false
        }
        if panelLayout.groups.isEmpty { inspectorVisible = false }
    }

    func selectPanelTab(_ panel: Panel) {
        guard let index = panelLayout.groupIndex(containing: panel) else { return }
        panelLayout.groups[index].selected = panel
        panelLayout.groups[index].collapsed = false
        panelRevealSuppressed = true
        activePanel = panel
        panelRevealSuppressed = false
        panelRevealTarget = panel
        panelRevealTick += 1
    }

    func togglePanelCollapsed(_ panel: Panel) {
        guard let index = panelLayout.groupIndex(containing: panel) else { return }
        panelLayout.groups[index].collapsed.toggle()
        if !panelLayout.groups[index].collapsed { selectPanelTab(panelLayout.groups[index].selected) }
    }

    func resetPanelLayout() {
        panelLayout = .standard
        selectPanelTab(.edit)
    }

    func movePanel(_ panel: Panel, by delta: Int) {
        guard let index = panelLayout.groupIndex(containing: panel) else { return }
        let target = index + delta
        guard panelLayout.groups.indices.contains(target) else { return }
        let moved = panelLayout.groups.remove(at: index)
        panelLayout.groups.insert(moved, at: target)
    }

    func movePanel(_ panel: Panel, before target: Panel) {
        guard panel != target, let source = panelLayout.groupIndex(containing: panel),
              panelLayout.groupIndex(containing: target) != nil else { return }
        if panelLayout.groups[source].tabs.contains(target) {
            var tabs = panelLayout.groups[source].tabs
            tabs.removeAll { $0 == panel }
            guard let at = tabs.firstIndex(of: target) else { return }
            tabs.insert(panel, at: at)
            panelLayout.groups[source].tabs = tabs
            return
        }
        panelLayout.groups[source].tabs.removeAll { $0 == panel }
        if panelLayout.groups[source].tabs.isEmpty {
            panelLayout.groups.remove(at: source)
        } else if panelLayout.groups[source].selected == panel {
            panelLayout.groups[source].selected = panelLayout.groups[source].tabs[0]
        }
        guard let targetIndex = panelLayout.groupIndex(containing: target),
              let tabIndex = panelLayout.groups[targetIndex].tabs.firstIndex(of: target) else { return }
        panelLayout.groups[targetIndex].tabs.insert(panel, at: tabIndex)
        panelLayout.groups[targetIndex].selected = panel
        panelLayout.groups[targetIndex].collapsed = false
        selectPanelTab(panel)
    }

    func movePanelToNewGroup(_ panel: Panel) {
        guard let index = panelLayout.groupIndex(containing: panel), panelLayout.groups[index].tabs.count > 1 else { return }
        panelLayout.groups[index].tabs.removeAll { $0 == panel }
        if panelLayout.groups[index].selected == panel {
            panelLayout.groups[index].selected = panelLayout.groups[index].tabs[0]
        }
        panelLayout.groups.insert(PanelDockGroup(tabs: [panel]), at: index + 1)
        selectPanelTab(panel)
    }

    func canMovePanel(_ panel: Panel, by delta: Int) -> Bool {
        guard let index = panelLayout.groupIndex(containing: panel) else { return false }
        return panelLayout.groups.indices.contains(index + delta)
    }

    /// Invoked by active-panel changes from desktop commands and shortcuts.
    func revealPanelInLayout(_ panel: Panel) {
        if let index = panelLayout.groupIndex(containing: panel) {
            panelLayout.groups[index].selected = panel
            panelLayout.groups[index].collapsed = false
        } else if let index = panelLayout.groups.firstIndex(where: { group in
            group.tabs.contains { Self.dockFamily($0) == Self.dockFamily(panel) }
        }) {
            panelLayout.groups[index].tabs.append(panel)
            panelLayout.groups[index].selected = panel
            panelLayout.groups[index].collapsed = false
        } else {
            panelLayout.groups.append(PanelDockGroup(tabs: [panel]))
        }
        inspectorVisible = true
        panelRevealTarget = panel
        panelRevealTick += 1
    }

    private static func dockFamily(_ panel: Panel) -> Int {
        switch panel {
        case .edit, .profiles, .presets: 0
        case .crop, .remove: 1
        case .masking, .redeye: 2
        case .info, .keywords: 3
        case .versions, .activity: 4
        }
    }
}
