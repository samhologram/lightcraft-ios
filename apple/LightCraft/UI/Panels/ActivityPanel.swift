import SwiftUI
@preconcurrency import LightCraftKit

/// History: undo / redo, the active photo's edit steps (tap to go back to one), and background tasks.
struct ActivityPanel: View {
    let model: LibraryModel

    private struct Step: Identifiable {
        let id: Int
        let label: String
    }

    private struct TaskRow: Identifiable {
        let id: UInt64
        let label: String
        let progress: String
    }

    @State private var steps: [Step] = []
    @State private var cursor = -1
    @State private var tasks: [TaskRow] = []

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Button { uiUndo(model) } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.state.canUndo)
                    .accessibilityIdentifier("command.edit.undo")
                    Button { uiRedo(model) } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.state.canRedo)
                    .accessibilityIdentifier("command.edit.redo")
                }
                .listRowBackground(Color.clear)
                if let label = model.state.undoLabel {
                    Text(verbatim: "Undo: \(label)").font(.footnote).foregroundStyle(.secondary)
                }
                if let label = model.state.redoLabel {
                    Text(verbatim: "Redo: \(label)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !tasks.isEmpty {
                Section("Background Tasks") {
                    ForEach(tasks) { t in
                        VStack(alignment: .leading) {
                            Text(verbatim: t.label)
                            Text(verbatim: t.progress).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("task.\(t.id)")
                    }
                }
            }
            Section("Edit Steps") {
                if steps.isEmpty {
                    Text("No edit steps for this photo.").foregroundStyle(.secondary)
                }
                ForEach(steps.reversed()) { s in
                    Button {
                        model.run("history.restore", ["index": s.id])
                    } label: {
                        HStack {
                            Text(verbatim: s.label)
                            Spacer()
                            if s.id == cursor { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .foregroundStyle(s.id > cursor ? Color.secondary : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.\(s.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
        .onChange(of: model.undoRedoTick) { _, _ in reload() }
    }

    private func reload() {
        if model.state.active != nil, let h = EngineQuery.json(model, "history.list") as? [String: Any] {
            let labels = (h["history"] as? [String]) ?? []
            steps = labels.enumerated().map { Step(id: $0.offset, label: $0.element) }
            cursor = (h["cursor"] as? NSNumber)?.intValue ?? (labels.count - 1)
        } else {
            steps = []
            cursor = -1
        }
        if let a = EngineQuery.json(model, "activity.list") as? [String: Any],
           let list = a["tasks"] as? [[String: Any]] {
            tasks = list.compactMap { t in
                guard let id = (t["id"] as? NSNumber)?.uint64Value else { return nil }
                let done = jsonNumber(t["done"]) ?? 0, total = jsonNumber(t["total"]) ?? 0
                return TaskRow(id: id, label: (t["label"] as? String) ?? (t["kind"] as? String) ?? "Task",
                               progress: total > 0 ? "\(Int(done)) / \(Int(total))" : ((t["detail"] as? String) ?? ""))
            }
        }
    }
}
