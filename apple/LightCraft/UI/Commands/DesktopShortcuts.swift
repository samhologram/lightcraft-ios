import SwiftUI
import UIKit
@preconcurrency import LightCraftKit

// Hardware-keyboard shortcuts of the desktop app (cookbook §4). Commands that have a menu item get their key
// from the menu bar (`LibraryCommands`); everything else (Lightroom's single keys P / X / U, 0-5 ratings,
// 6-9 colour labels, arrows, \ and so on) is a zero-size hidden button on the editor and grid views.
// All bare keys are switched off while a text field is being edited.

// MARK: - Text focus

/// Whether a text field or text view is the first responder anywhere in the app. SwiftUI's `TextField`,
/// `.searchable` and `TextEditor` are `UITextField` / `UITextView` underneath and post these notifications.
@MainActor @Observable
final class TextFocusMonitor {
    static let shared = TextFocusMonitor()

    private(set) var isEditing = false
    @ObservationIgnored private var tokens: [any NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let begin: [Notification.Name] = [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        let end: [Notification.Name] = [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification]
        for name in begin {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isEditing = true }
            })
        }
        for name in end {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isEditing = false }
            })
        }
    }
}

// MARK: - Hidden shortcut buttons

extension View {
    /// Adds the desktop's keyboard shortcuts (the ones the menu bar does not bind) as hidden buttons.
    func desktopShortcuts(model: LibraryModel) -> some View {
        background { DesktopShortcutLayer(model: model) }
    }
}

struct DesktopShortcutLayer: View {
    let model: LibraryModel

    private let monitor = TextFocusMonitor.shared

    private enum Action {
        case command(String)
        case rate(Int)
        case label(String)
    }

    private struct Item: Identifiable {
        let id: String
        let label: String
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let action: Action
        var isArrow: Bool {
            modifiers.isEmpty && [KeyEquivalent.leftArrow, .rightArrow, .upArrow, .downArrow].contains(key)
        }
    }

    /// Ids that other views bind already (`LibraryRootView.ShortcutButtons`).
    private static let boundElsewhere: Set<String> = ["view.gridToggle", "view.detail"]

    private static let items: [Item] = {
        var out: [Item] = []
        var taken = Set<String>()
        func take(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> Bool {
            taken.insert("\(key.character)-\(modifiers.rawValue)").inserted
        }
        // Combinations the menu bar owns.
        for id in MenuLayout.menuBoundIDs {
            if let shortcut = MenuLayout.shortcuts[id] { _ = take(shortcut.key, shortcut.modifiers) }
        }
        // Catalog shortcuts of commands without a menu item (the desktop's keys, same keys).
        for (id, shortcut) in MenuLayout.shortcuts.sorted(by: { $0.key < $1.key }) {
            guard !MenuLayout.menuBoundIDs.contains(id), !boundElsewhere.contains(id),
                  !id.hasPrefix("panel."), !id.hasPrefix("tool."),
                  take(shortcut.key, shortcut.modifiers) else { continue }
            out.append(Item(id: id, label: CommandCatalog.shared.label(id), key: shortcut.key,
                            modifiers: shortcut.modifiers, action: .command(id)))
        }
        // Lightroom's rating digits and colour-label digits (desktop: 0-5, 6-9), plus aliases.
        for n in 0...5 where take(KeyEquivalent(Character("\(n)")), []) {
            out.append(Item(id: "photo.rate.\(n)", label: n == 0 ? String(localized: "No Rating") : String(localized: "Set Rating \(n)"),
                            key: KeyEquivalent(Character("\(n)")), modifiers: [], action: .rate(n)))
        }
        for (digit, label) in [("6", "red"), ("7", "yellow"), ("8", "green"), ("9", "blue")] where take(KeyEquivalent(Character(digit)), []) {
            out.append(Item(id: "photo.label.\(label)", label: String(localized: "Label \(label.capitalized)"),
                            key: KeyEquivalent(Character(digit)), modifiers: [], action: .label(label)))
        }
        if take("e", .shift) {
            out.append(Item(id: "dialog.export", label: CommandCatalog.shared.label("dialog.export"), key: "e", modifiers: .shift, action: .command("dialog.export")))
        }
        if take("+", []) {
            out.append(Item(id: "view.thumbSizeUp.plus", label: CommandCatalog.shared.label("view.thumbSizeUp"), key: "+", modifiers: [], action: .command("view.thumbSizeUp")))
        }
        return out
    }()

    private var active: Bool {
        !monitor.isEditing && model.pendingCommand == nil && !model.showCommandPalette && !model.showExport
    }

    private var gridWithoutEngineList: Bool { model.mode == .grid && !model.samplesMode }

    private func fire(_ action: Action) {
        switch action {
        case .command(let id):
            guard model.isEnabled(id) else { return }
            UICatalog.invoke(id, model: model)
        case .rate(let n):
            guard model.isEnabled("photo.rate") else { return }
            model.run("photo.rate", ["rating": n])
        case .label(let name):
            guard model.isEnabled("photo.label") else { return }
            model.run("photo.label", ["label": name])
        }
    }

    var body: some View {
        let skipArrows = gridWithoutEngineList
        Group {
            ForEach(Self.items) { item in
                if !(skipArrows && item.isArrow) {
                    Button(item.label) { fire(item.action) }
                        .keyboardShortcut(item.key, modifiers: item.modifiers)
                        .accessibilityIdentifier("shortcut.\(item.id)")
                }
            }
            // Space toggles fit / 100 % in the loupe (desktop alias of Z).
            if model.mode == .loupe {
                Button("Toggle Zoom") { fire(.command("view.zoomToggle")) }
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityIdentifier("shortcut.view.zoomToggle.space")
            }
            // Escape returns to the grid; Return finishes the active tool (full screen has its own Esc).
            if model.mode == .loupe, !model.canvasOnly, model.activeTool == nil {
                Button("Back to Grid") { model.runUI("view.back") }
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("shortcut.view.back")
            }
            if model.mode == .loupe, model.activeTool != nil {
                Button("Done") { model.runUI("tool.done") }
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("shortcut.tool.done")
            }
        }
        .disabled(!active)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Multi-finger taps

extension View {
    /// Two-finger tap = undo, three-finger tap = redo, anywhere over this view (single-finger taps, pinch and
    /// pan are untouched: the recognizers live on the window and only start for touches inside the view).
    func multiFingerUndoRedo(model: LibraryModel) -> some View {
        background {
            MultiFingerTaps(
                onTwoFingerTap: { if model.state.canUndo { model.undo() } },
                onThreeFingerTap: { if model.state.canRedo { model.redo() } })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct MultiFingerTaps: UIViewRepresentable {
    let onTwoFingerTap: @MainActor () -> Void
    let onThreeFingerTap: @MainActor () -> Void

    func makeUIView(context: Context) -> TapProbeView {
        let view = TapProbeView()
        view.onTwo = onTwoFingerTap
        view.onThree = onThreeFingerTap
        return view
    }

    func updateUIView(_ view: TapProbeView, context: Context) {
        view.onTwo = onTwoFingerTap
        view.onThree = onThreeFingerTap
    }
}

/// An invisible view that hosts two tap recognizers on its window. They do not cancel touches, recognize
/// alongside every other gesture, and ignore touches that start outside this view's bounds.
final class TapProbeView: UIView, UIGestureRecognizerDelegate {
    var onTwo: (@MainActor () -> Void)?
    var onThree: (@MainActor () -> Void)?

    private var recognizers: [UITapGestureRecognizer] = []
    private weak var host: UIWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        let two = makeRecognizer(touches: 2, action: #selector(twoTapped))
        let three = makeRecognizer(touches: 3, action: #selector(threeTapped))
        window.addGestureRecognizer(two)
        window.addGestureRecognizer(three)
        recognizers = [two, three]
        host = window
    }

    private func makeRecognizer(touches: Int, action: Selector) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer(target: self, action: action)
        tap.numberOfTouchesRequired = touches
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        return tap
    }

    private func detach() {
        for recognizer in recognizers { host?.removeGestureRecognizer(recognizer) }
        recognizers = []
        host = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { detach() }
    }

    @objc private func twoTapped() { onTwo?() }
    @objc private func threeTapped() { onThree?() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        window != nil && bounds.contains(touch.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
