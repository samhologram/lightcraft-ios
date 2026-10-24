import Foundation

/// Panel state API: open / toggle / hide / collapse / reorder. The Window menu and keyboard shortcuts call
/// `showPanel(_:)` and `togglePanel(_:)`; the iPad inspector column and the iPhone sheet render the result.
extension LibraryModel {
    /// True when the panel is on screen: a section in the iPad column, or the panel in the iPhone sheet.
    func isPanelShown(_ panel: Panel) -> Bool {
        guard inspectorVisible else { return false }
        return panelsAsSheet ? activePanel == panel : panelLayout.isVisible(panel)
    }

    /// Opens the panel (the loupe, the inspector, and for the column: unhides, expands, scrolls to it).
    func showPanel(_ panel: Panel) {
        openPanel(panel)  // sets `activePanel`, whose didSet unhides / expands / reveals it in the layout
        revealPanelInLayout(panel)
    }

    /// Shows the panel (a collapsed one opens), or hides it when it is already shown and open (the iPhone sheet closes instead).
    func togglePanel(_ panel: Panel) {
        if !isPanelShown(panel) || (!panelsAsSheet && panelLayout.isCollapsed(panel)) {
            showPanel(panel)
        } else if panelsAsSheet {
            inspectorVisible = false
        } else {
            hidePanel(panel)
        }
    }

    /// Takes a panel out of the iPad column (the column closes when none is left).
    func hidePanel(_ panel: Panel) {
        if panelsAsSheet {
            if activePanel == panel { inspectorVisible = false }
            return
        }
        panelLayout.hidden.insert(panel)
        if activePanel == panel, let next = panelLayout.visiblePanels.first(where: { !panelLayout.isCollapsed($0) }) ?? panelLayout.visiblePanels.first {
            panelRevealSuppressed = true
            activePanel = next
            panelRevealSuppressed = false
        }
        if panelLayout.visiblePanels.isEmpty { inspectorVisible = false }
    }

    func setPanelCollapsed(_ panel: Panel, _ collapsed: Bool) {
        if collapsed { panelLayout.collapsed.insert(panel) } else { panelLayout.collapsed.remove(panel) }
    }

    /// Expands a collapsed panel and makes it the active one (the crop overlay, tools and shortcuts follow the active panel).
    func togglePanelCollapsed(_ panel: Panel) {
        if panelLayout.isCollapsed(panel) {
            setPanelCollapsed(panel, false)
            panelRevealSuppressed = true
            activePanel = panel
            panelRevealSuppressed = false
        } else {
            setPanelCollapsed(panel, true)
        }
    }

    func collapseAllPanels() { panelLayout.collapsed = Set(Panel.allCases) }
    func expandAllPanels() { panelLayout.collapsed = [] }
    func resetPanelLayout() { panelLayout = .standard }

    /// Moves a panel up (-1) or down (+1) among the shown panels.
    func movePanel(_ panel: Panel, by delta: Int) {
        var shown = panelLayout.visiblePanels
        guard let i = shown.firstIndex(of: panel) else { return }
        let j = i + delta
        guard shown.indices.contains(j) else { return }
        shown.swapAt(i, j)
        applyShownOrder(shown)
    }

    /// Drag and drop: puts `panel` where `target` is.
    func movePanel(_ panel: Panel, before target: Panel) {
        guard panel != target else { return }
        var shown = panelLayout.visiblePanels
        guard let from = shown.firstIndex(of: panel), let to = shown.firstIndex(of: target) else { return }
        shown.remove(at: from)
        shown.insert(panel, at: to)
        applyShownOrder(shown)
    }

    func canMovePanel(_ panel: Panel, by delta: Int) -> Bool {
        let shown = panelLayout.visiblePanels
        guard let i = shown.firstIndex(of: panel) else { return false }
        return shown.indices.contains(i + delta)
    }

    /// Writes a new order of the shown panels, leaving the hidden ones at their slots.
    private func applyShownOrder(_ shown: [Panel]) {
        var queue = shown[...]
        panelLayout.order = panelLayout.order.map { panelLayout.isVisible($0) ? queue.popFirst() ?? $0 : $0 }
    }

    /// Layout part of opening a panel: unhide, expand, ask the column to scroll to it.
    func revealPanelInLayout(_ panel: Panel) {
        var layout = panelLayout
        layout.hidden.remove(panel)
        layout.collapsed.remove(panel)
        if layout != panelLayout { panelLayout = layout }
        panelRevealTarget = panel
        panelRevealTick += 1
    }
}
